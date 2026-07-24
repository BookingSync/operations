# frozen_string_literal: true

# Implements a generic Sidekiq wrapper for any operation.
#
# @example
#
#   Operations::Sidekiq::Command.new(Rental::Create.default, try_call: false).call(params, **context)
#
class Operations::Sidekiq::Command
  extend Dry::Initializer
  include Dry::Equalizer(:operation_class_name, :operation_method_name, :try_call, :delay, :time, :sidekiq_options)
  include Dry::Monads[:result]

  param :operation_class_name
  param :operation_method_name, Operations::Types::Coercible::String
  option :try_call, Operations::Types::Bool
  option :delay, Operations::Types::Integer.optional, optional: true
  option :time, Operations::Types::Time.optional, optional: true
  option :sidekiq_options, Operations::Types::Hash, optional: true, default: proc { {} }
  option :job_class, optional: true, default: proc { Operations::Sidekiq::Job }

  def in(delay)
    self.class.new(
      operation_class_name, operation_method_name,
      try_call: try_call, delay: delay, sidekiq_options: sidekiq_options, job_class: job_class
    )
  end

  def at(time)
    self.class.new(
      operation_class_name, operation_method_name,
      try_call: try_call, time: time, sidekiq_options: sidekiq_options, job_class: job_class
    )
  end

  def set(**sidekiq_options)
    self.class.new(
      operation_class_name, operation_method_name,
      try_call: try_call, delay: delay, time: time, sidekiq_options: sidekiq_options, job_class: job_class
    )
  end

  def call(params, **context)
    perform_args = [
      operation_class_name,
      operation_method_name,
      serializer.call(params),
      serializer.call(context),
      try_call ? "try_call!" : "call!"
    ]

    Success(jid: schedule_job(perform_args))
  end

  private

  def schedule_job(perform_args)
    job = job_class
    job = job.set(**sidekiq_options) if sidekiq_options.present?

    if time
      job.perform_at(time, *perform_args)
    elsif delay
      job.perform_in(delay, *perform_args)
    else
      job.perform_async(*perform_args)
    end
  end

  def serializer
    @serializer ||= Operations::Sidekiq::Serializer.new
  end
end
