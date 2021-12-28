# frozen_string_literal: true

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
#   operation = Operation::Composite.new(
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
#       @default ||= Operation::Composite.new(new, ...)
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
# 3. Precondition is checking if the operation is possible to
#    perform for the current domain state. For example, if
#    {Booking::Cancel} is possible to execute for a particular booking.
#    There might be multiple checks, so precondition returns either
#    a Symbol code designating the particular check failure or `nil`
#    which means the checks have passed. Like Policy it heavily relies
#    on the context (either initial or the data loaded by the contract).
#    Anything that has nothing to do with the user input validation
#    should be implemented as a precondition.
# 4. Operation itself implements the routine. It can create or update
#    enities, send API requiests, send notifications, communicate with
#    the bus. Anything that should be done as a part of the operation.
#    Operation returns a Result monad (either Success or Failure).
#    See {https://dry-rb.org/gems/dry-monads/1.3/} for details. Also,
#    it is better to use Do notation for the implementation. If Success
#    result contains a hash, it is returned as a part of the context.
# 5. After calls run after the operation was successful and transaction
#    was committed. Composite adds the result of the after calls to the
#    operation result but in case of unsuccessful after calls, the
#    operation is still marked as successful. Each particular after
#    entry is wrapped inside of a dedicated DB transaction.
#    Given this, avoid putting business logic here, only something
#    that can be replayed. Each callable object is expected to have the
#    same method's signature as operation's `call` method.
#
# Every method in {Operation::Composite} returns {Operation::Result} instance,
# which contains all the artifacts and the information about the errors
# should they ever happen.
class Operation::Composite
  UNDEFINED = Object.new.freeze
  EMPTY_HASH = {}.freeze
  COMPONENTS = %i[contract policies preconditions operation after].freeze
  FORM_HYDRATOR = ->(_form_class, params, **_context) { params }
  ERROR_REPORTER = lambda do |message, payload|
    Sentry.capture_message(message, extra: payload)
  end
  TRANSACTION = ->(&block) { ActiveRecord::Base.transaction(&block) }

  include Dry::Monads[:result]
  include Dry::Monads::Do.for(:call_monad, :callable_monad)
  include Dry::Equalizer(*COMPONENTS)
  extend Dry::Initializer

  class OperationFailed < StandardError
  end

  param :operation, Types.Interface(:call)
  option :contract, Types.Interface(:call)
  option :policies, Types::Array.of(Types.Interface(:call))
  option :preconditions, Types::Array.of(Types.Interface(:call)), default: -> { [] }
  option :after, Types::Array.of(Types.Interface(:call)), default: -> { [] }
  option :form_model_map, Types::Hash.map(
    Types::Coercible::Array.of(Types::String | Types::Symbol | Types.Instance(Regexp)),
    Types::String
  ), default: proc { {} }
  option :form_base, Types::Class, default: proc { ::Operation::Form }
  option :form_class, Types::Class, default: proc { build_form }
  option :form_hydrator, Types.Interface(:call), default: proc { FORM_HYDRATOR }
  option :error_reporter, Types.Interface(:call), default: proc { ERROR_REPORTER }
  option :transaction, Types.Interface(:call), default: proc { TRANSACTION }

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
  # This plays really well with {Operation::Convenience}
  #
  # @see {https://dry-rb.org/gems/dry-initializer/3.0/ for details}
  # @see Operation::Convenience
  def self.build(operation, contract = nil, **deps)
    options = {
      contract: (contract || operation::Contract).new(**deps),
      policies: [operation::Policy.new(**deps)]
    }
    options[:preconditions] = [operation::Precondition.new(**deps)] if operation.const_defined?(:Precondition)

    new(operation.new(**deps), **options)
  end

  def initialize(operation, policy: UNDEFINED, policies: [UNDEFINED], precondition: nil, preconditions: [], **options)
    policies_sum = Array.wrap(policy) + policies
    result_policies = policies_sum - [UNDEFINED] unless policies_sum == [UNDEFINED, UNDEFINED]
    options[:policies] = result_policies if result_policies

    preconditions.concat([precondition]) if precondition.present?
    super(operation, preconditions: preconditions, **options)
  end

  # Executes all the components in a particular order. Returns the result
  # on any step failure. First it validates the user input with the contract
  # then it checks the policy and preconditions and if everything passes -
  # executes the operation routine.
  # The whole process always happens inside of a DB transaction.
  def call(params, **context)
    operation_result(unwrap_monad(call_monad(params, context)))
  end

  # Works the same way as `call` but raises an exception on operation failure.
  def call!(params, **context)
    result = call(params, **context)
    raise OperationFailed.new(result.pretty_inspect) if result.failure?

    result
  end

  # Checks if the operation is possible to call in the current context.
  # Performs both: policy and preconditions checks.
  def callable(params = EMPTY_HASH, **context)
    operation_result(unwrap_monad(callable_monad(component(:contract).call(params, context))))
  end

  # Works the same way as `callable` but checks only the policy.
  def allowed(params = EMPTY_HASH, **context)
    operation_result(component(:policies).call(params, context))
  end

  # Works the same way as `callable` but checks only preconditions.
  def possible(params = EMPTY_HASH, **context)
    operation_result(component(:preconditions).call(params, context))
  end

  # These 3 methods added for convenience. They return boolean result
  # instead of Operation::Result. True on success and false on failure.
  %i[callable allowed possible].each do |method|
    define_method "#{method}?" do |**kwargs|
      public_send(method, **kwargs).success?
    end
  end

  def pretty_print(pp)
    attributes = self.class.dry_initializer.attributes(self)

    pp.object_group(self) do
      pp.seplist(attributes.keys, -> { pp.text "," }) do |name|
        pp.breakable " "
        pp.group(1) do
          pp.text name.to_s
          pp.text " = "
          pp.pp send(name)
        end
      end
    end
  end

  private

  def component(identifier)
    (@components ||= {})[identifier] = begin
      "::Operation::Components::#{identifier.to_s.camelize}".constantize.new(
        send(identifier),
        message_resolver: contract.message_resolver,
        error_reporter: error_reporter,
        transaction: transaction
      )
    end
  end

  def call_monad(params, context)
    result = transaction.call do
      contract_result = component(:contract).call(params, context)

      yield callable_monad(contract_result)
      yield contract_result
      yield component(:operation).call(contract_result.params, contract_result.context)
    end

    Success(component(:after).call(result.params, result.context))
  end

  def callable_monad(contract_result)
    # We need to check policies/preconditions at the beginning.
    # But since contract loads entities, we need to run it first.
    yield contract_result if contract_result.failure? && !contract_has_all_required_context?(contract_result.context)

    yield component(:policies).call(contract_result.params, contract_result.context)
    component(:preconditions).call(contract_result.params, contract_result.context)
  end

  def contract_has_all_required_context?(context)
    required_context = component(:policies).required_context | component(:preconditions).required_context
    (required_context - context.keys).empty?
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

  def build_form
    ::Operation::FormBuilder
      .new(base_class: form_base)
      .build(
        key_map: contract.class.schema.key_map,
        namespace: operation.class,
        class_name: form_class_name,
        model_map: form_model_map
      )
  end

  def form_class_name
    "#{contract.class.name.demodulize.delete_suffix("Contract")}Form" if contract.class.name
  end
end
