# frozen_string_literal: true

require "operations/components"
require "operations/components/contract"
require "operations/components/policies"
require "operations/components/preconditions"
require "operations/components/idempotency"
require "operations/components/operation"
require "operations/components/on_success"
require "operations/components/on_failure"
# This is an entry point interface for every operation in
# the operations layer. Every operation instance consists of 4
# components: contract, policy, preconditions and operation
# routine. Each component is a class that implements `call`
# instance method.
#
# @example
#
#   repo = SomeRepo.new
#
#   operation = Operations::Command.new(
#     OperationClass.new(repo: repo),
#     contract: ContractClass.new(repo: repo),
#     policies: PolicyClass.new,
#     preconditions: PreconditionClass.new
#   )
#
#   operation.call(params, context)
#   operation.callable(context)
#
# Operation has an application lifetime. This means that the
# instance is created on the application start-up and supposed
# to be completely stateless. Each component also supposed
# to be stateless with the dependencies (like repositories or
# API clients passed on initialization).
#
# Since operations have an application lifetime, they have to be
# easily accessible from somewhere. The most perfect place for storing
# them (as for a lot of other concepts like repositories) would be
# an application container. But until we introduced it - operation
# can be memoized in the operation's class method.
#
# @example
#
#   class Namespace::OperationName
#     def self.default
#       @default ||= Operations::Command.new(new, ...)
#     end
#   end
#
#   Namespace::OperationName.default.call(params, ...)
#
# The main 2 entry point methods are: {#call} and {#callable}.
# The first one will perform the whole routime and the second
# one will check if it is possible to perform the routine at
# this moment since policy or preconditions can prevent it.
#
# Each of the methods accepts 2 arguments: params and context:
#
# 1. Params is purely a user input, which is passed to the contract
#    coercion and validation.
# 2. Context has 2 roles: it holds the initial context like `current_user`
#    or anything that can't be received from the user but is required
#    by the operation. Also, it can be enriched by the contract later.
#
# When we check {#callable}, params can be ommited since we don't
# have them at the moment and they will not affect the returned value.
# Put it is still possible to pass them if they are required by some
# reason.
#
# Now, components. The `call` functions of each component are
# executed in a particular order. Each component has its purpose:
#
# 1. Contract (which is a standard {Dry::Validation::Contract})
#    has a responsibility of validating the user input, coercing
#    the values and enriching the initial context by e.g. loading
#    entities from the DB. After the contract evaluation, there
#    should be everything in the context that is required for the
#    rest of the steps. This happens in the contract's rules.
#    Contract returns a standard {Dry::Validation::Result}.
#    See {https://dry-rb.org/gems/dry-validation/1.5/} for details.
# 2. Policy checks if the operation is allowed for execution. Mostly by
#    the current user but there might be other options. The policy
#    retuns a boolean result. Allowed or not. Policy relies mostly on
#    the initial context but can also use the results of the Contract
#    rules evaluation.
# 3. Idempotency check are running after policy and before preconditions and
#    can return either Success() or Failure({}). In case of Failure, preconditions,
#    the operation body (and after calls) will be skept but the operation
#    result will be successful. Failure({}) can carry an additional context
#    to make sure the operation result context is going to be the same for both
#    cases of normal operation execution and skipped operation body. The
#    only sign of the execution interrupted at this stage will be the
#    value of {Result#component} equal to `:idempotency`.
# 4. Precondition is checking if the operation is possible to
#    perform for the current domain state. For example, if
#    {Booking::Cancel} is possible to execute for a particular booking.
#    There might be multiple checks, so precondition returns either
#    a Symbol code designating the particular check failure or `nil`
#    which means the checks have passed. Like Policy it heavily relies
#    on the context (either initial or the data loaded by the contract).
#    Anything that has nothing to do with the user input validation
#    should be implemented as a precondition.
# 5. Operation itself implements the routine. It can create or update
#    enities, send API requiests, send notifications, communicate with
#    the bus. Anything that should be done as a part of the operation.
#    Operation returns a Result monad (either Success or Failure).
#    See {https://dry-rb.org/gems/dry-monads/1.3/} for details. Also,
#    it is better to use Do notation for the implementation. If Success
#    result contains a hash, it is returned as a part of the context.
# 6. `on_success` calls run after the operation was successful and transaction
#    was committed. Composite adds the result of the `on_success` calls to the
#    operation result but in case of failed `on_success` calls, the
#    operation is still marked as successful. Each particular `on_success`
#    entry is wrapped inside of a dedicated DB transaction.
#    Given this, avoid putting business logic here, only something
#    that can be replayed. Each callable object is expected to have the
#    same method's signature as operation's `call` method.
# 7. `on_failure` calls run after the operation failed and transaction
#    was rolled back. Composite adds the result of the `on_failure` calls to the
#    operation result. Each particular `on_failure`
#    entry is wrapped inside of a dedicated DB transaction.
#
# Every method in {Operations::Command} returns {Operations::Result} instance,
# which contains all the artifacts and the information about the errors
# should they ever happen.
class Operations::Command
  COMPONENTS = %i[contract policies idempotency preconditions operation on_success on_failure].freeze
  FORM_HYDRATOR = ->(_form_class, params, **_context) { params }

  extend Dry::Initializer
  include Dry::Core::Constants
  include Dry::Monads[:result]
  include Dry::Monads::Do.for(:call_monad, :callable_monad, :validate_monad, :execute_operation)
  include Dry::Equalizer(*COMPONENTS)

  # Provides message and meaningful sentry context for failed operations
  class OperationFailed < StandardError
    attr_reader :operation_result

    def initialize(operation_result)
      @operation_result = operation_result
      operation_class_name = operation_result.operation&.operation&.class&.name

      super("#{operation_class_name} failed on #{operation_result.component}")
    end

    def sentry_context
      operation_result.as_json(include_command: true)
    end
  end

  param :operation, Operations::Types.Interface(:call)
  option :contract, Operations::Types.Interface(:call)
  option :policies, Operations::Types::Array.of(Operations::Types.Interface(:call))
  option :idempotency, Operations::Types::Array.of(Operations::Types.Interface(:call)), default: -> { [] }
  option :preconditions, Operations::Types::Array.of(Operations::Types.Interface(:call)), default: -> { [] }
  option :on_success, Operations::Types::Array.of(Operations::Types.Interface(:call)), default: -> { [] }
  option :on_failure, Operations::Types::Array.of(Operations::Types.Interface(:call)), default: -> { [] }
  option :form_model_map, Operations::Form::DeprecatedLegacyModelMapImplementation::TYPE, default: proc { {} }
  option :form_base, Operations::Types::Class, default: proc { ::Operations::Form::Base }
  option :form_class, Operations::Types::Class.optional, default: proc {}, reader: false
  option :form_hydrator, Operations::Types.Interface(:call), default: proc { FORM_HYDRATOR }
  option :configuration, Operations::Configuration, default: proc { Operations.default_config }

  include Operations::Inspect.new(dry_initializer.attributes(self).keys)

  # A short-cut to initialize operation by convention:
  #
  # Namespace::OperationName - operation
  # Namespace::OperationName::Contract - contract
  # Namespace::OperationName::Policies - policies
  # Namespace::OperationName::Preconditions - preconditions
  #
  # All the dependencies are passed to every component's
  # initializer, so they'd be better tolerant to unknown
  # dependencies. Luckily it is easily achievable with {Dry::Initializer}.
  # This plays really well with {Operations::Convenience}
  #
  # @see {https://dry-rb.org/gems/dry-initializer/3.0/ for details}
  # @see Operations::Convenience
  def self.build(operation, contract = nil, **deps)
    options = {
      contract: (contract || operation::Contract).new(**deps),
      policies: [operation::Policy.new(**deps)]
    }
    options[:preconditions] = [operation::Precondition.new(**deps)] if operation.const_defined?(:Precondition)

    new(operation.new(**deps), **options)
  end

  def initialize(
    operation, policy: Undefined, policies: [Undefined],
    precondition: nil, preconditions: [], after: [], **options
  )
    policies_sum = Array.wrap(policy) + policies
    result_policies = policies_sum - [Undefined] unless policies_sum == [Undefined, Undefined]
    options[:policies] = result_policies if result_policies

    if after.present?
      ActiveSupport::Deprecation.new.warn("Operations::Command `after:` option is deprecated and will be " \
        "removed in 1.0.0. Please use `on_success:` instead")
    end

    preconditions.push(precondition) if precondition.present?
    super(operation, preconditions: preconditions, on_success: after, **options)
  end

  # Instantiates a new command with the given fields updated.
  # Useful for defining multiple commands for a single operation body.
  def merge(**changes)
    self.class.new(operation, **self.class.dry_initializer.attributes(self), **changes)
  end

  # Executes all the components in a particular order. Returns the result
  # on any step failure. First it validates the user input with the contract
  # then it checks the policy and preconditions and if everything passes -
  # executes the operation routine.
  # The whole process always happens inside of a DB transaction.
  def call(params, **context)
    operation_result(unwrap_monad(call_monad(params.to_h, context)))
  end

  # Works the same way as `call` but raises an exception on operation failure.
  def call!(params, **context)
    result = call(params, **context)
    raise OperationFailed.new(result) if result.failure?

    result
  end

  # Calls the operation and raises an exception in case of a failure
  # but only if preconditions and policies have passed.
  # This means that the exception will be raised only on contract
  # or the operation body failure.
  def try_call!(params, **context)
    result = call(params, **context)
    raise OperationFailed.new(result) if result.failure? && !result.failed_precheck?

    result
  end

  # Checks if the operation is valid to call in the current context and parameters.
  # Performs policy preconditions and contract checks.
  def validate(params, **context)
    operation_result(unwrap_monad(validate_monad(params.to_h, context)))
  end

  # Checks if the operation is possible to call in the current context.
  # Performs both: policy and preconditions checks.
  def callable(params = EMPTY_HASH, **context)
    operation_result(unwrap_monad(callable_monad(component(:contract).call(params.to_h, context))))
  end

  # Works the same way as `callable` but checks only the policy.
  def allowed(params = EMPTY_HASH, **context)
    operation_result(component(:policies).call(params.to_h, context))
  end

  # Works the same way as `callable` but checks only preconditions.
  def possible(params = EMPTY_HASH, **context)
    operation_result(component(:preconditions).call(params.to_h, context))
  end

  # These 3 methods added for convenience. They return boolean result
  # instead of Operations::Result. True on success and false on failure.
  %i[callable allowed possible].each do |method|
    define_method :"#{method}?" do |**kwargs|
      public_send(method, **kwargs).success?
    end
  end

  # Returns boolean result instead of Operations::Result for validate method.
  # True on success and false on failure.
  def valid?(*args, **kwargs)
    validate(*args, **kwargs).success?
  end

  def to_hash
    {
      **main_components_to_hash,
      **form_components_to_hash,
      configuration: configuration
    }
  end

  def form_class
    @form_class ||= build_form_class
  end

  private

  def main_components_to_hash
    {
      operation: operation.class.name,
      contract: contract.class.name,
      policies: policies.map { |policy| policy.class.name },
      idempotency: idempotency.map { |idempotency_check| idempotency_check.class.name },
      preconditions: preconditions.map { |precondition| precondition.class.name },
      on_success: on_success.map { |on_success_component| on_success_component.class.name },
      on_failure: on_failure.map { |on_failure_component| on_failure_component.class.name }
    }
  end

  def form_components_to_hash
    {
      form_model_map: form_model_map,
      form_base: form_base.name,
      form_class: form_class.name,
      form_hydrator: form_hydrator.class.name
    }
  end

  def component(identifier)
    (@components ||= {})[identifier] = begin
      component_kwargs = {
        message_resolver: contract.message_resolver,
        info_reporter: configuration.info_reporter,
        error_reporter: configuration.error_reporter
      }
      component_kwargs[:after_commit] = configuration.after_commit if identifier == :on_success
      callable = send(identifier)

      "::Operations::Components::#{identifier.to_s.camelize}".constantize.new(
        callable,
        **component_kwargs
      )
    end
  end

  def call_monad(params, context)
    operation_result = unwrap_monad(execute_operation(params, context))

    return operation_result unless operation_result.component == :operation

    component = operation_result.success? ? component(:on_success) : component(:on_failure)
    component.call(operation_result)
  end

  def execute_operation(params, context)
    configuration.transaction.call do
      contract_result = yield validate_monad(params, context, call_idempotency: true)

      yield component(:operation).call(contract_result.params, contract_result.context)
    end
  end

  def validate_monad(params, context, call_idempotency: false)
    contract_result = component(:contract).call(params, context)

    yield callable_monad(contract_result, call_idempotency: call_idempotency)

    contract_result
  end

  def callable_monad(contract_result, call_idempotency: false)
    # We need to check policies/preconditions at the beginning.
    # But since contract loads entities, we need to run it first.
    yield contract_result if contract_result.failure? && !component(:policies).callable?(contract_result.context)
    yield component(:policies).call(contract_result.params, contract_result.context)

    if call_idempotency
      idempotency_result = yield component(:idempotency)
        .call(contract_result.params, contract_result.context)
    end

    yield contract_result if contract_result.failure? && !component(:preconditions).callable?(contract_result.context)
    preconditions_result = yield component(:preconditions).call(contract_result.params, contract_result.context)

    idempotency_result || preconditions_result
  end

  def operation_result(result)
    result.merge(operation: self)
  end

  def unwrap_monad(result)
    case result
    when Success
      result.value!
    when Failure
      result.failure
    else
      result
    end
  end

  def build_form_class
    ::Operations::Form::Builder
      .new(base_class: form_base)
      .build(
        key_map: contract.class.schema.key_map,
        model_map: Operations::Form::DeprecatedLegacyModelMapImplementation.new(form_model_map),
        namespace: operation.class,
        class_name: form_class_name,
        persisted: true
      )
  end

  def form_class_name
    "#{contract.class.name.demodulize.delete_suffix("Contract")}Form" if contract.class.name
  end
end
