class TestJob < ApplicationJob
    queue_as :default
  
    def perform()
      throw "Error on test job"
    end
end
  