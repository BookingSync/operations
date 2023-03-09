# frozen_string_literal: true

# This is a the result of the operation. Considered a failure if contains
# any errors. Contains all the execution artifacts such as params and context
# (the initial one merged with the result of contract and operation routine
# execution).
# Also able to spawn a form object basing on the operation params and errors.
class Operations::Result
  include Dry::Monads[:result]
  include Dry::Equalizer(:operation, :component, :params, :context, :on_success, :errors)
  extend Dry::Initializer

  option :operation, type: Operations::Types::Instance(Operations::Command), optional: true
  option :component, type: Operations::Types::Symbol.enum(*Operations::Command::COMPONENTS)
  option :params, type: Operations::Types::Hash.map(Operations::Types::Symbol, Operations::Types::Any)
  option :context, type: Operations::Types::Hash.map(Operations::Types::Symbol, Operations::Types::Any)
  option :on_success, type: Operations::Types::Array.of(Operations::Types::Any), default: proc { [] }
  option :on_failure, type: Operations::Types::Array.of(Operations::Types::Any), default: proc { [] }
  option :errors, type: Operations::Types.Interface(:call) | Operations::Types::Instance(Dry::Validation::MessageSet),
    default: proc { Dry::Validation::MessageSet.new([]).freeze }

  # Instantiates a new result with the given fields updated
  def merge(**changes)
    self.class.new(**self.class.dry_initializer.attributes(self), **changes)
  end

  def errors(**options)
    if @errors.respond_to?(:call)
      @errors.call(**options)
    else
      options.empty? ? @errors : @errors.with([], options).freeze
    end
  end

  def success?
    errors.empty?
  end
  alias_method :callable?, :success?

  def failure?
    !success?
  end

  # Checks if ANY of the passed precondition or policy codes have failed
  # If nothing is passed - checks that ANY precondition or policy have failed
  def failed_precheck?(*error_codes)
    failure? &&
      %i[policies preconditions].include?(component) &&
      (error_codes.blank? || errors_with_code?(*error_codes))
  end
  alias_method :failed_prechecks?, :failed_precheck?

  # Checks if ANY of the passed policy codes have failed
  # If nothing is passed - checks that ANY policy have failed
  def failed_policy?(*error_codes)
    component == :policies && failed_precheck?(*error_codes)
  end
  alias_method :failed_policies?, :failed_policy?

  # Checks if ANY of the passed precondition codes have failed
  # If nothing is passed - checks that ANY precondition have failed
  def failed_precondition?(*error_codes)
    component == :preconditions && failed_precheck?(*error_codes)
  end
  alias_method :failed_preconditions?, :failed_precondition?

  def to_monad
    success? ? Success(self) : Failure(self)
  end

  # A form object that can be used for rendering forms with `form_for`,
  # `simple_form` and other view helpers.
  def form
    @form ||= operation.form_class.new(
      operation.form_hydrator.call(operation.form_class, params, **context),
      messages: errors.to_h
    )
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

  def as_json(*, include_command: false, **)
    hash = {
      component: component,
      params: params,
      context: context_as_json,
      on_success: on_success.as_json,
      on_failure: on_failure.as_json,
      errors: errors(full: true).to_h
    }
    hash[:command] = operation.as_json if include_command
    hash
  end

  private

  def errors_with_code?(name, *names)
    names = [name] + names
    (errors.map { |error| error.meta[:code] } & names).present?
  end

  def context_as_json
    context.transform_values do |context_value|
      next context_value.class.name unless context_value.respond_to?(:id)

      [context_value.class.name, context_value.id].join("#")
    end
  end
end
