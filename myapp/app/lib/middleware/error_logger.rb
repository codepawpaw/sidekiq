module Middleware
    class ErrorLogger
        def initialize(options=nil)
        # options == { :foo => 1, :bar => 2 }
        end

        def call(worker, job, queue)
            begin
                yield
            rescue => ex
                puts ex.message
            end
        end
    end
end