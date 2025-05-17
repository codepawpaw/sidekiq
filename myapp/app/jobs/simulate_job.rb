class SimulateJob < ApplicationJob
    queue_as :default
  
    def perform()
      throw "Error on simulate job"
    end
end
  