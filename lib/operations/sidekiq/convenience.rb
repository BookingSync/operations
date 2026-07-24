# frozen_string_literal: true

# A short-cut for {Operations::Sidekiq::Command} definition.
#
# @example
#
#   class Rental::Create
#     extend Operations::Sidekiq::Convenience
#
#     def self.default
#       @default ||= Operations::Command.new(...)
#     end
#   end
#
#   # This will do `Rental::Create.default.call!(params, **context)` inside the job
#   Rental::Create.default_async.call(params, **context)
#   Rental::Create.default_async.in(5.minutes).set(queue: :slow).call(params, **context)
#
#   # This will do `Rental::Create.default.try_call!(params, **context)` inside the job
#   Rental::Create.default_try_async.call(params, **context)
#   Rental::Create.default_try_async.in(5.minutes).set(queue: :slow).call(params, **context)
#
module Operations::Sidekiq::Convenience
  def self.[](on_retries_exhausted: nil, job_class: nil, delay: nil, **sidekiq_options)
    Module.new do
      define_singleton_method(:extended) do |base|
        base.extend Operations::Sidekiq::Convenience
        base.instance_variable_set(:@sidekiq_options, sidekiq_options)
        base.instance_variable_set(:@on_retries_exhausted, on_retries_exhausted)
        base.instance_variable_set(:@job_class, job_class)
        base.instance_variable_set(:@delay, delay)
      end
    end
  end

  def on_retries_exhausted
    @on_retries_exhausted
  end

  def method_missing(name, ...)
    name_without_suffix = name.to_s.delete_suffix("_async").delete_suffix("_try").to_sym

    if name.to_s.end_with?("_async") && respond_to?(name_without_suffix)
      ivar_name = :"@#{name}"

      if instance_variable_defined?(ivar_name)
        instance_variable_get(ivar_name)
      else
        instance_variable_set(ivar_name, build_sidekiq_command(name, name_without_suffix))
      end
    else
      super
    end
  end

  private

  def build_sidekiq_command(name, name_without_suffix)
    options = { try_call: name.to_s.end_with?("_try_async"), sidekiq_options: @sidekiq_options || {} }
    options[:job_class] = @job_class if @job_class
    options[:delay] = @delay if @delay
    Operations::Sidekiq::Command.new(self.name, name_without_suffix, **options)
  end

  def respond_to_missing?(name, *)
    (name.to_s.end_with?("_async") && respond_to?(name.to_s.delete_suffix("_async").delete_suffix("_try").to_sym)) ||
      super
  end
end
