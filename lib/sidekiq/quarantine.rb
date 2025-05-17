require "sidekiq/component"
require 'set'
require 'json'
require 'time'

module Sidekiq
  class Quarantine
    include Sidekiq::Component

    QUARANTINE_LIST_KEY = "quarantine:jobs"
    JOB_FAILURE_COUNT_KEY_PREFIX = "quarantine:job_failures:"
    WATCHED_CLASSES_SET_KEY = "quarantine:watched_classes"

    def initialize()
      @max_failures_before_quarantine = 5
    end

    def watch_class(class_name)
      redis { |c| c.sadd(WATCHED_CLASSES_SET_KEY, class_name.to_s) }
    end

    def unwatch_class(class_name)
      redis { |c| c.srem(WATCHED_CLASSES_SET_KEY, class_name.to_s) }
    end

    def watched_classes
      redis { |c| c.smembers(WATCHED_CLASSES_SET_KEY) }.to_set
    end

    def is_watched?(class_name)
      redis { |c| c.sismember(WATCHED_CLASSES_SET_KEY, class_name.to_s) }
    end

    def add_job_to_quarantine(job_payload_hash, reason = "unknown")
      # Ensure we have a clean hash and not a Sidekiq::Job object or JSON string
      job_payload = job_payload_hash.is_a?(String) ? Sidekiq.load_json(job_payload_hash) : job_payload_hash.dup
      
      job_payload['quarantined_at'] = Time.now.utc.iso8601
      job_payload['quarantine_reason'] = reason

      redis do |conn|
        conn.rpush(QUARANTINE_LIST_KEY, Sidekiq.dump_json(job_payload))
        # If the job was auto-quarantined due to failures, reset its failure count
        # to prevent immediate re-quarantining if it's retried from quarantine later.
        clear_quarantine_failure_count(job_payload['jid']) if job_payload['jid']
      end
      Sidekiq.logger.info "[Quarantine] Job #{job_payload['class']} (JID: #{job_payload['jid']}) copied to quarantine. Reason: #{reason}."
    end

    def get_quarantined_jobs(start = 0, stop = -1)
      redis do |conn|
        conn.lrange(QUARANTINE_LIST_KEY, start, stop).map do |job_str|
          begin
            Sidekiq.load_json(job_str)
          rescue JSON::ParserError
            Sidekiq.logger.error "[Quarantine] Failed to parse job from quarantine: #{job_str[0..100]}..."
            nil
          end
        end.compact
      end
    end

    def count_quarantined_jobs
      redis { |c| c.llen(QUARANTINE_LIST_KEY) }
    end

    def clear_quarantine_failure_count(jid)
      return unless jid
      redis { |c| c.del("#{JOB_FAILURE_COUNT_KEY_PREFIX}#{jid}") }
    end

    def record_failure_and_quarantine_if_needed(job_payload)
      puts "============================= [Quarantine] Record Failure and quarantine ============================"
      job_class_name = job_payload['class']
      return unless job_class_name.is_a?(String) && !job_class_name.empty?
      return unless is_watched?(job_class_name)

      jid = job_payload['jid']
      if jid.nil? || jid.empty?
        Sidekiq.logger.warn "[Quarantine] Job #{job_class_name} has no JID, cannot track failures for quarantine."
        return
      end

      failure_key = "#{JOB_FAILURE_COUNT_KEY_PREFIX}#{jid}"
      
      current_failure_count = redis do |conn|
        count = conn.incr(failure_key)
        # Optional: Set an expiry on this failure count key
        # conn.expire(failure_key, 24 * 60 * 60 * 7) # e.g., 7 days
        count
      end

      if current_failure_count >= @max_failures_before_quarantine
        reason = "#{current_failure_count} failures (threshold: #{@max_failures_before_quarantine})"
        add_job_to_quarantine(job_payload, reason)
      end
    end
  end
end