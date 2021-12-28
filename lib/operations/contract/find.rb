# frozen_string_literal: true

# Implements `find` macro for the base contract.
# This macro gives an ability to look up for entities
# by the given key and store them into the operation
# context.
#
# TODO: The class is unfinished, there is a lot of refactoring awaits.
class Operation::Contract::Find
  extend Dry::Initializer

  DEFAULT_METHOD = :get_by

  param :context_key
  option :optional, default: proc { false }
  option :model_name, default: proc { context_key.to_s.classify }
  option :repo_name, default: proc { :"#{context_key}_repository" }
  option :aggregate_key, default: proc { :"#{context_key}_aggregate" }
  option :by, optional: true
  option :field, default: proc { by || :"#{context_key}_id" }
  option :method, optional: true
  option :aggregate, optional: true

  def required?
    !optional
  end

  def entity_name
    context_key.to_s.humanize
  end

  def generic_repo
    GenericRepository.new(model_name.constantize)
  end

  def get(repo, value)
    if method
      repo.public_send(method, value)
    else
      column = by || :id
      method = :"#{DEFAULT_METHOD}_#{column}"

      if repo.respond_to?(method)
        repo.public_send(method, value)
      else
        repo.public_send(DEFAULT_METHOD, column => value)
      end
    end
  end

  def wrap_entity(entity, repo:)
    return {} unless aggregate

    entity = repo.class.from_db(entity) unless entity.is_a?(Domain::Entity)

    {
      context_key => entity,
      aggregate_key => aggregate.new(entity)
    }
  end
end
