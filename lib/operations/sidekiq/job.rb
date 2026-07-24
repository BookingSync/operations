# frozen_string_literal: true

# Executes an operation whenever {Operations::Sidekiq::Command} is used.
#
# We need this generic job in order to avoid creating multiple tiny
# boilerplate job classes. Internally, it uses serialization to
# be able to overcome Sidekiq argument type limitations.
#
# Applications that want to add instrumentation (e.g. a Sentry scope
# or a transaction name) around the operation call can subclass this
# job and override {#instrument}:
#
#   class OperationJob < Operations::Sidekiq::Job
#     private
#
#     def instrument(container_class)
#       Sentry.configure_scope do |scope|
#         scope.set_transaction_name("Sidekiq/OperationJob/#{container_class}")
#         yield
#       end
#     end
#   end
class Operations::Sidekiq::Job
  include ::Sidekiq::Job

  sidekiq_options queue: :default

  sidekiq_retries_exhausted do |msg, _exception|
    container_class, _, params, context = msg["args"]
    container_class = container_class.constantize
    next unless container_class.respond_to?(:on_retries_exhausted) && container_class.on_retries_exhausted

    deserializer = Operations::Sidekiq::Deserializer.new
    params = deserializer.call(params)
    context = deserializer.call(context)

    container_class.on_retries_exhausted.call!(params, **context)
  end

  def perform(container_class, container_method, params, context, operation_method = "call!")
    deserializer = Operations::Sidekiq::Deserializer.new
    operation = container_class.constantize.send(container_method)
    params = deserializer.call(params)
    context = deserializer.call(context)

    instrument(container_class) do
      operation.public_send(operation_method, params, **context)
    rescue => e
      raise wrap_with_operation_error(container_class, container_method, e)
    end
  end

  private

  # Hook for wrapping the operation call with application-specific
  # instrumentation. The default implementation simply yields.
  def instrument(_container_class)
    yield
  end

  def wrap_with_operation_error(container_class, container_method, err)
    parts = "#{container_class}::#{container_method.capitalize}Async".split("::")
    operation_error_class = parts.inject(Object) do |obj, part|
      obj.const_defined?(part) ? obj.const_get(part) : obj.const_set(part, Module.new)
    end
    operation_error = operation_error_class.const_set(:Error, Class.new(StandardError)).new(err)
    operation_error.tap { |error| error.set_backtrace(err.backtrace) }
  end
end
