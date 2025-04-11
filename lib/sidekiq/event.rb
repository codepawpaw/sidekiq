require 'concurrent/hash'
require 'forwardable'
require 'time'

module Sidekiq
  class Event
    class << self
      def subscribers
        @subscribers ||= Concurrent::Hash.new { |hash, key| hash[key] = }
      end

      # def subscribe(event_name, subscriber = nil, &block)
      #   callable = subscriber || block

      #   unless callable.respond_to?(:call)
      #     raise ArgumentError, "Subscriber must be a callable object (respond to #call) or a block."
      #   end

      #   subscribers[event_name.to_sym]
      #   # Use compute to ensure atomic update if necessary, though append is often safe enough here
      #   subscribers.compute(event_name.to_sym) { |existing| (existing ||) + [callable] }
      #   Sidekiq.logger.debug { "Sidekiq::Events: Registered subscriber #{callable.inspect} for event :#{event_name}" }
      #   true
      # end

      # def publish(event_name, payload)
      #   event_sym = event_name.to_sym
      #   return unless events_enabled?
      #   registered_subscribers = subscribers[event_sym]
      #   return if registered_subscribers.nil? || registered_subscribers.empty?

      #   Sidekiq.logger.debug { "Sidekiq::Events: Publishing event :#{event_sym} with payload #{payload.inspect} to #{registered_subscribers.count} subscribers" }

      #   registered_subscribers.each do |subscriber|
      #     begin
      #       subscriber.call(payload.dup) # Pass a duplicated payload to prevent modification by subscribers
      #     rescue StandardError => e
      #       error_message = "Sidekiq::Events: Subscriber #{subscriber.inspect} failed for event :#{event_sym}. Error: #{e.class}: #{e.message}"
      #       Sidekiq.logger.error(error_message)
      #       Sidekiq.logger.error(e.backtrace.join("\n"))
      #       # Optionally, publish a meta-event about the subscriber failure
      #       # publish(:subscriber_error, {... details... })
      #     end
      #   end
      # end

      # def clear_subscribers!
      #   subscribers.clear
      # end

      def build_processor_payload(event_name, job_payload, process_info)
        payload = {
          event_name: event_name,
          timestamp: Time.now.utc,
          jid: job_payload['jid'],
          worker_class: job_payload['class'],
          queue: job_payload['queue'],
          job_payload: job_payload,
          process_info: process_info
        }
        payload
      end
  
      def build_process_info
        {
          pid: Process.pid,
          tid: Thread.current.object_id.to_s(36),
          identity: Sidekiq.identity,
          hostname: Socket.gethostname
        }
      end
    end
  end
end