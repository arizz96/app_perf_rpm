module AppPerfRpm
  class Tracer
    class << self
      def trace_id
        Thread.current[:trace_id]
      end

      def trace_id=(t)
        Thread.current[:trace_id] = t
      end

      def tracing?
        Thread.current[:tracing]
      end

      def tracing=(t)
        Thread.current[:tracing] = t
      end

      def start_instance(layer, opts = {})
        Instance.new(layer, opts)
      end

      def in_trace?
        !Thread.current[:trace_id].nil?
      end

      def trace?(duration = 0)
        rand * 100 < ::AppPerfRpm.worker.configuration.sample_rate.to_i
      end

      def start_trace(layer, opts = {})
        self.tracing = ::AppPerfRpm::Tracer.trace?

        if tracing?
          self.trace_id ||= opts.delete(:trace_id) || generate_trace_id
          result = trace(layer, opts) do
            yield
          end
          self.trace_id = nil
        else
          result = yield
        end

        result
      end

      def trace(layer, opts = {})
        self.tracing = ::AppPerfRpm::Tracer.trace? if tracing?.nil?

        result = nil

        if tracing?
          start = Time.now.to_f
          result = yield
          duration = (Time.now.to_f - start) * 1000

          event = [layer, trace_id, start, duration, YAML::dump(opts)]
          ::AppPerfRpm.store(event)
        else
          result = yield
        end

        result
      end

      def log_event(event, opts = {})
        ::AppPerfRpm.log_event([event, generate_trace_id, Time.now.to_f, opts])
      end

      def generate_trace_id
        Digest::SHA1.hexdigest([Time.now, rand].join)
      end

      class Instance
        attr_accessor :layer, :opts, :start, :duration

        def initialize(layer, opts = {})
          self.layer = layer
          self.opts = opts
          self.start = Time.now.to_f
        end

        def finish(opts = {})
          self.opts.merge!(opts)
          self.duration = (Time.now.to_f - start) * 1000
        end

        def submit(opts = {})
          if ::AppPerfRpm::Tracer.tracing?
            self.opts.merge!(opts)
            event = [layer, trace_id, start, duration, opts.to_json]
            ::AppPerfRpm.store(event)
          end
        end

        private

        def trace_id
          ::AppPerfRpm::Tracer.trace_id
        end
      end
    end
  end
end
