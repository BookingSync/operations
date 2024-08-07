# Operations

## A bit of theory

### What is an operation

First of all, let's define an application as a combination of domain logic and application state. Domain logic can either read and return the parts of the application state to the consumer (Query) or can modify the application state (Command).

**Note:** There is a concept that is called Command Query Separation (CQS) or Command Query Responsibility Segregation (CQRS) and which can be used at any level of the implementation (classes in OOP, API) but the general idea is simply not to mix these two up.

While Query is a simple concept (just fetch data from the application state and render it to the consumer in the requested form), Command implementation can have a lot of caveats.

_Command_ or _business operation_ or _interaction_ or _use case_ or _application service_ (DDD term) even just _service_ (this term is so ambiguous) is a predefined sequence of programmed actions that can be called by a user (directly in the code or via the API) and modifies the application state. In the scope of this framework, we prefer the _operation_ term though.

These modifications are atomic in the sense that the application state is supposed to be consistent and valid after the operation execution. It might be eventually consistent but the idea is that the application state is valid after the operation execution and in a normal case, there should be no need to call a complimentary operation to make the state valid.

Operations can also create different side effects such as: sending an email message, making asynchronous API calls (shoot-and-forget), pushing events to an event bus, etc.

**Note:** An important note is that contrary to the pure DDD approach that considers aggregate a transactional boundary, in this framework - the operation itself is wrapped inside of a transaction, though it is configurable.

The bottom line here is: any modifications to the application state, whether it is done via controller or Sidekiq job, or even console should happen in operations. Operation is the only entry point to the domain modification.

### The Rails way

In a classic Rails application, the role of business operations is usually played by ActiveRecord models. When a single model implements multiple use cases, it creates messy noodles of code that are trying to incorporate all the possible paths of execution. This leads to a lot of not funny things including conditional callbacks and virtual attributes on models. Simply put, this way violates the SRP principle and the consequences are well known.

Each operation in turn contains a single execution routine, a single sequence of program calls that is easy to read and modify.

This approach might look more fragile in the sense that ActiveRecord big ball of mud that might look like centralized logic storage and if we will not use it, we might miss important parts of domain logic and produce an invalid application state (e.g. after each update an associated record in the DB supposed to be updated somehow). This might be the case indeed but it can be easily solved by using a tiny bit of determination. The benefits of the operations approach easily overweigh this potential issue.

### Operations prerequisites

Operations are supposed to be the first-class citizens of an application. This means that ideally application state is supposed to be modified using operations exclusively. There are some exceptions though:

* In tests, sometimes it is faster and simpler to create an application state using direct storage calls (factories) since the desired state might be a result of multiple operations' calls which can be omitted for the sake of performance.
* When the running application state is inconsistent or invalid, there might not be an appropriate operation implemented to fix the state. So we have to use direct storage modifications.

**NOTE:** When application state is valid but an appropriate operation does not exist, it is better to create one. Especially if the requested state modification needs to happen more than 1 time.

### Alternatives

There are many alternatives to this framework in the Rails world such as:

* https://github.com/AaronLasseigne/active_interaction
* https://github.com/toptal/granite
* https://github.com/trailblazer/trailblazer

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'operations'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install operations

## Usage

### Getting started

The simplest operation that is implemented with the framework will look like this:

```ruby
create_user = Operations::Command.new(
  User::Create.new,
  contract: User::CreateContract.new,
  policy: nil
)

create_user.call({ email: "user@gmail.com" })
```

Where the operation body is implemented as:

```ruby
class User::Create
  include Dry::Monads[:result]

  def call(params, **)
    user = User.new(params)
    if user.save
      Success(user: user)
    else
      Failure(:user_not_created)
    end
  end
end
```

And the contract as:

```ruby
class User::CreateContract < Operations::Contract
  params do
    required(:email).filled(:string, format?: URI::MailTo::EMAIL_REGEXP)
  end
end
```

Where `Operations::Contract` is actually a [Dry::Validation::Contract](https://dry-rb.org/gems/dry-validation/) with tiny additions.

Everything in the framework is built with the composition over inheritance approach in mind. An instance of `Operations::Command` essentially runs a pipeline through the steps passed into the initializer. In this particular case, the passed parameters will be validated by the contract and if everything is good, will be passed into the operation body.

**Important:** the whole operation pipeline (except [callbacks](#callbacks-on-success-on-failure)) is wrapped within a transaction by default. This behavior can be adjusted by changing `Operations::Configuration#transaction` (see [Configuration](#configuration) section).

### Operation Result

A result of any operation call is an instance of `Operation::Result` which contains all the necessary information:

```ruby
create_user.call({ email: "user@gmail.com" }) #=>
# #<Operations::Result ...>,
#  component = :operation,
#  params = {:email=>"user@gmail.com"},
#  context = {:user=>#<User ...>},
#  on_success = [],
#  on_failure = [],
#  errors = #<Dry::Validation::MessageSet messages=[] options={}>>
```

* `component` - the stage where execution stopped. If it operation failed on precondition it is going to be `:preconditions`. See `Operations::Command::COMPONENTS` for the full list.
* `params` - params passed to the operation `call` and other methods.
* `context` - initial context merged with the context generated by operation body returned in Success() monad.
* `on_success`, `on_failure` - corresponding callback results.
* `errors` - a list of errors returned by contract/policies/preconditions.

There are several useful methods on `Operations::Result`:

* `success?`, `failure?` - checks for errors presence.
* `errors(full: true)` - this is not only an attribute but also a method accepting additional params just like `Dry::Validation::Contract#errors` does.
* `failed_policy?`, `failed_precondition?`, `failed_precheck?` - checks whether the operation failed on policy, precondition, or any of them respectively. It is possible to check for exact error codes as well.

### Params and context

Every operation input consists of 2 components: params and context. Params is a hash and it is passed as a hash argument while context is passed as kwargs.

Params are used to pass user input. It will be coerced by the contract implementation and will contain only simple types like strings or integers.
Context should never contain any user input and used to pass contextual data like current_user or, say, ActiveRecord models that were fetched from DB before the operation call.

```ruby
create_post.call({ title: "Post Title" }, current_user: current_user)
```

The context will be passed further to every component in the pipeline:

```ruby
class Post::Create
  def call(params, current_user:, **)
    current_user.posts.new(params)

    Success({})
  end
end
```

A rule of thumb: context conveys all the data you don't want to be passed by the user.

### Contract

Besides params coercion, a contract is responsible for filling in additional context. In Dry::Validation, rules are used to perform this:

```ruby
class Post::UpdateContract < Operations::Contract
  params do
    required(:post_id).filled(:integer)
    required(:title).filled(:string)
  end

  rule(:post_id) do |context:|
    context[:post] = Post.find(value)
  end
end
```

Then, the operation body can proceed with the found post handling:

```ruby
class Post::Update
  def call(params, post:, **)
    post.update(params)

    Success({})
  end
end
```

A more advanced example of finding ActiveRecord records:

```ruby
class Post::UpdateContract < Operations::Contract
  params do
    optional(:post_id).filled(:integer)
    required(:title).filled(:string)
  end

  rule do |context:|
    next key.failure(:key?) unless key?(:post_id) && context[:post]

    post = Post.find_by(id: values[:comment_id])

    if post
      context[:post] = post
    else
      key.failure(:not_found)
    end
  end
end
```

**Important:** Please check [Generic preconditions and policies](#generic-preconditions-and-policies) on reasons why we don't assign nil post to the context.

Now notice that `post_id` param became optional and `required` validation is handled by the rule conditionally. This allows passing either param or a post instance itself if it exists:

```ruby
post_update.call({ post_id: 123 })
post_update.call({}, post: post)
```

Both of the calls above are going to work exactly alike but in the first case, there will be an additional database query.

It is possible to extract context filling into some kind of generic macro:

```ruby
class OperationContract < Operations::Contract
  def self.find(context_key)
    rule do |context:|
      params_key = :"#{name}_id"

      next key.failure(:key?) unless key?(params_key) && context[context_key]

      record = context_key.to_s.classify.constantize.find_by(id: values[params_key])

      if record
        context[context_key] = record
      else
        key.failure(:not_found, tokens: { context_key: context_key })
      end
    end
  end
end

class Post::UpdateContract < OperationContract
  params do
    optional(:post_id).filled(:integer)
    required(:title).filled(:string)
  end

  find :post
end
```

**Important:** contract is solely responsible for populating operation context from given params. At the same time, it should be flexible enough to accept the passed context for optimization purposes.

### Operation body

The operation body can be any callable object (respond to the `call` method), even a lambda. But it is always better to define it as a class since there might be additional instance methods and [dependency injections](#dependency-injection).

In any event, the operation body should return a Dry::Monads::Result instance. In case of a Failure, it will be converted into an `Operation::Result#error` and in case of Success(), its content will be merged into the operation context.

**Important:** since the Success result payload is merged inside of a context, it is supposed to be a hash.

### Application container

Operations are built using the principle: initializers are for [dependencies](#dependency-injection). This means that the Command instance is supposed to be initialized once for the application lifetime and is a perfect candidate for some kind of application container to be stored in.

But if your application does not have an application container - the best approach would be to use class methods to store Command instances.

```ruby
class Post::Update
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: User::CreateContract.new,
      policy: nil
    )
  end

  def call(params, post: **)
  end
end
```

And then this command can be called from anywhere (for example, controller) using:

```ruby
def update
  post_update = Post::Update.default.call(params[:post], current_user: current_user)

  if post_update.success?
    redirect_to(post_path(post_update.context[:post].id))
  else
    render :edit
  end
end
```

### Dependency Injection

Dependency injection can be used to provide IO clients with the operation. It could be DB repositories or API clients. The best way is to use Dry::Initializer for it since it provides the ability to define acceptable types.

If you still prefer to use ActiveRecord, it is worth creating a wrapper around it providing Dry::Monads-compatible interfaces.

```ruby
class ActiveRecordRepository
  include Dry::Monads[:result]
  extend Dry::Initializer

  param :model, type: Types::Class.constrained(lt: ActiveRecord::Base)

  def create(**attributes)
    record = model.new(**attributes)

    if record.save
      Success(model.name.underscore.to_sym => record) # Success(post: record)
    else
      failure_from_errors(record.errors) # Failure([{ message: "Must be present", code: :blank, path: "title" }])
    end
  end

  private

  def failure_from_errors(errors)
    failures = errors.map do |error|
      { message: error.message, code: error.type, path: error.attribute }
    end
    Failure(failures)
  end
end
```

Then this repository can be used in the operation directly:

```ruby
class Post::Create
  extend Dry::Initializer

  option :post_repository, default: proc { ActiveRecordRepository.new(Post) }

  def call(params, **)
    post_repository.create(**params)
  end
end
```

`ActiveRecordRepository#create` returns a proper Success() monad which will become a part of `Operation::Result#context` returned by Composite or a properly built Failure() monad which will be incorporated into `Operation::Result#errors`.

Of course, it is possible to use [dry-auto_inject](https://dry-rb.org/gems/dry-auto_inject/) along with [dry-container](https://dry-rb.org/gems/dry-container/) to make things even fancier.

### Configuration

The gem has a global default configuration:

```ruby
Operations.configure(
  error_reporter: -> (message, payload) { Sentry.capture_message(message, extra: payload) },
)
```

But also, a configuration instance can be passed directly to a Command initializer (for example, to switch off the wrapping DB transaction for a single operation):

```ruby
Operations::Command.new(..., configuration: Operations.default_config.new(transaction: -> {}))
```

It is possible to call `configuration_instance.new` to receive an updated configuration instance since it is a `Dry::Struct`

### Preconditions

When we need to check against the application state, preconditions are coming to help. Obviously, we can do all those checks in Contract rule definitions but it is great to have separate kinds of components (a separate stage in the pipeline) for this particular reason as it gives the ability to check them in isolation.

There are many potential scenarios when it can be handy. For example, we might need to render a button only when the subject entity satisfies preconditions for a particular operation. Or we want to return a list of possible operations from an API we have.

**Important:** a rule of thumb here is that preconditions don't depend on the user input, they only check the existing state of the application and they are supposed to access only the operation context for this purpose, not params.

```ruby
class Post::Publish
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Contract.new,
      policy: nil,
      preconditions: [NotPublishedPrecondition.new]
    )
  end

  def call(_, post:, **)
    post.update(published_at: Time.zone.now)

    Success({})
  end
end

class Post::Publish::Contract < OperationContract
  params do
    optional(:post_id).filled(:integer)
  end

  find :post
end

class Post::Publish::NotPublishedPrecondition
  include Dry::Monads[:result]

  def call(post:, **)
    return Failure(:already_published) if post.published?

    Success()
  end
end
```

Precondition is supposed to return either a Success() monad if an operation is ok to proceed with the updates or `Failure(:error_symbol)` if we want to interrupt the operation execution.

Besides just a symbol, it is possible to return a Failure with a hash:

```ruby
class Post::Publish::NotPublishedPrecondition
  include Dry::Monads[:result]

  def call(post:, **)
    return Failure(error: :already_published, tokens: { published_at: post.published_at }) if post.published?

    Success()
  end
end
```

Then `tokens:` values can be used in the translation string: `Post is already published at %{published_at}` as a way to provide more context to the end user.

```ruby
result = Post::Publish.default.call({ post_id: 123 }) #=>
# #<Operations::Result ...>,
#  component = :preconditions,
#  params = {:post_id=>123},
#  context = {:post=>#<Post id=123, ...>},
#  on_success = [],
#  on_failure = [],
#  errors = #<Dry::Validation::MessageSet messages=[
#    #<Dry::Validation::Message text="Post is already published at 20.02.2023 12:00" path=[nil] meta={:code=>:already_published}>
#  ] options={}>>
result.failed_precheck? #=> true
result.failed_precondition? #=> true
result.failed_policy? #=> false
result.failed_precondition?(:already_published) #=> true
result.failed_precheck?(:already_published) #=> true
result.failed_precondition?(:another_code) #=> false
result.failed_precheck?(:another_code) #=> false
```

Alternatively, it is possible to return either just an error_symbol or `nil` from the precondition where nil is interpreted as a lack of error. In this case, the precondition becomes a bit less bulky:

```ruby
class Post::Publish::NotPublishedPrecondition
  def call(post:, **)
    :already_published if post.published?
  end
end
```

It is up to the developer which notion to use but we recommend a uniform application-wide approach to be established.

To resolve an error message from an error code, the contract's MessageResolver is used. So the rules are the same as for the failures returned by `Operations::Contract`.

It is possible to pass multiple preconditions. They will be evaluated all at once and if even one of them fails - the operation fails as well.

```ruby
class Post::Publish
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Contract.new,
      policy: nil,
      preconditions: [
        NotPublishedPrecondition.new,
        ApprovedPrecondition.new
      ]
    )
  end
end

class Post::Publish::ApprovedPrecondition
  def call(post:, **)
    :not_approved_yet unless post.approved?
  end
end
```

Now we want to render a button in the interface:

```erb
<% if Post::Publish.default.callable?(post: @post) %>
  <% link_to "Publish post", publish_post_url, method: :patch %>
<% end %>
```

In this case, you may notice that the post was found before in the controller action and since we have a smart finder rule in the contract, the operation is not going to need `post_id` param and will utilize the given `@post` instance.

There are 4 methods to be used for such checks:

* `possible(**context)` - returns an operation result (success or failure depending on precondition checks result). Useful when you need to check the exact error that happened.
* `possible?(**context)` - the same as the previous one but returns a boolean result.
* `callable(**context)` - checks for both preconditions and [policies](#policies).
* `callable?(**context)` - the same as the previous one but returns a boolean result.

`callable/callable?` will be the method used in 99% of cases, there are very few situations when one needs to check preconditions separately from policies.

### Policies

Now we need to check if the current actor can perform the operation. Policies are utilized for this purpose:

```ruby
class Post::Publish
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Contract.new,
      policy: AuthorPolicy.new,
    )
  end

  def call(_, post:, **)
    post.update(published_at: Time.zone.now)

    Success({})
  end
end

class Post::Publish::AuthorPolicy
  def call(post:, current_user:, **)
    post.author == current_user
  end
end
```

The difference between policies and preconditions is simple: policies generally involve current actor checks against the rest of the context while preconditions check the rest of the context without the actor's involvement. Both should be agnostic of user input.

Policies are separate from preconditions because in we usually treat the results of those checks differently. For example, if an operation fails on preconditions we might want to render a disabled button with an error message as a hint but if the policy fails - we don't render the button at all.

Similarly to preconditions, policies are having 2 returned values signatures: `true/false` and `Success()/Failure(:error_code)`. In case of `false`, an `:unauthorized` error code will be returned as a result. It is possible to return any error code using the `Failure` monad.

```ruby
class Post::Publish::AuthorPolicy
  include Dry::Monads[:result]

  def call(post:, current_user:, **)
    post.author == current_user ? Success() : Failure(:not_an_author)
  end
end
```

It is possible to pass multiple policies, and all of them have to succeed similarly to preconditions. Though it is impossible not to pass any policies for security reasons. If an operation is internal to the system and not exposed to the end user, `policy: nil` should be passed to `Operations::Command` instance anyway just to explicitly specify that this operation doesn't have any policy.

There are 2 more methods to check for policies separately:

* `allowed(**context)` - returns an operation result (success or failure depending on policy checks result). Useful when you need to check the exact error that happened.
* `allowed?(**context)` - the same as the previous one but returns a boolean result.

### ActiveRecord scopes usage

There might be a temptation to use AR scopes while fetching records from the DB. For example:

```ruby
class Post::Publish::Contract < Operations::Contract
  params do
    optional(:post_id).filled(:integer)
  end

  rule do |context:|
    next key.failure(:key?) unless key?(:post_id) && context[:post]

    post = context[:current_user].posts.publishable.find_by(id: values[:post_id])

    if post
      context[:post] = post
    else
      key.failure(:not_found) unless post
    end
  end
end
```

Please avoid this at all costs since:

1. It is possible to pass context variables like `post` explicitly and there is no guarantee that it will be scoped.
2. We want to return an explicit `unauthorized/not_publishable` error to the user instead of a cryptic `not_found`.
3. It does not fit the concept of repositories.

If we want to use security through obscurity in the controller later - we can easily turn a particular operation error into an `ActiveRecord::RecordNotFound` exception at will.

There could be non-domain but rather technical scopes like soft deletion used as an exception but this is a rare case and it should be carefully considered.

### Generic preconditions and policies

Normally we would expect the following execution order of the operation:

1. Set all the context
2. Check policies
3. Check preconditions
4. Validate user input
5. Call operation if everything is valid

This order is expected because it doesn't even make sense to validate user input if the state of the system or the current actor doesn't fit the requirements for the operation to be performed. This is also useful since we want to check if an operation is callable in some instances but we don't have user input at this point (e.g. on operation button rendering).

Unfortunately, to set the context, we need some of the user input (like `post_id`) to be validated. Separating context-filling params from the rest of them would cause 2 different contracts and other unpleasant or even ugly solutions. So to keep a single contract, the decision was to implement the following algorithm:

1. Validate user input in the contract
2. Try to set context if possible in contract rules
3. If the contract fails, don't return failure just yet
4. Check policies if we have all the required context set
5. Check preconditions if we have all the required context set
6. Return contract error if it was impossible to check preconditions/policies or they have passed
7. Call operation if everything is valid

This way we don't have to separate user input validation but the results returned will be very close to what the first routine would produce.

Since all the context variables are passed as kwargs to policies/preconditions, it is quite simple to determine if we have all the context required to run those policies/preconditions:

```ruby
class Comment::Update::NotSoftDeletedPrecondition
  def call(comment:, **)
    :soft_deleted if comment.deleted_at?
  end
end
```

Now we decided that we want this precondition to apply to all the models and be universal.

```ruby
class Preconditions::NotSoftDeleted
  extend Dry::Initializer

  param :context_key, Types::Symbol

  def call(**context)
    :soft_deleted if context[context_key].deleted_at?
  end
end

class Comment::Update
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Contract.new,
      preconditions: [Preconditions::NotSoftDeleted.new(:comment)],
      policy: nil
    )
  end
end
```

In this example, we pass the context key to check in the precondition initializer. And the algorithm that checks for the filled context is now unable to determine the required kwargs since there are no kwargs.

Fortunately, `context_key` or `context_keys` are magic parameter names that are also considered by this algorithm along with kwargs, so this example will do the trick and these magic variables are making generic policies/preconditions possible to define.

```ruby
class Policies::BelongsToUser
  extend Dry::Initializer

  param :context_key, Types::Symbol

  def call(current_user: **context)
    context[context_key].user == current_user
  end
end

class Comment::Update
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Contract.new,
      policy: Policies::BelongsToUser.new(:comment)
    )
  end
end
```

In the examples above we safely assume that the context key is present in the case when the contract and context population is implemented the following way:

```ruby
class Comment::Update::Contract < OperationContract
  params do
    optional(:comment_id).filled(:integer)
  end

  find :comment
end
```

The context key is not even set if the object was not found. In this case, the context will be considered insufficient and operation policies/preconditions will not be even called accordingly to the algorithm described above.

### Callbacks (on_success, on_failure)

Sometimes we need to run further application state modifications outside of the operation transaction. For this purpose, there are 2 separate callbacks: `on_success` and `on_failure`.

The key difference besides one running after operation success and another - after failure, is that `on_success` runs after the transaction commit. This means that if one operation calls another operation inside of it and the inner one has `on_success` callbacks defined - the callbacks are going to be executed only after the outermost transaction is committed successfully.

To achieve this, the framework utilizes the [after_commit_everywhere](https://github.com/Envek/after_commit_everywhere) gem and the behavior is configurable using `Operations::Configuration#after_commit` option.

It is a good idea to use these callbacks to schedule some jobs instead of just running inline code since if callback execution fails - the failure will be ignored and the operation is still going to be successful. Though the failure from both callbacks will be reported using `Operations::Configuration#error_reporter` and using Sentry by default.

```ruby
class Comment::Update
  def self.default
    @default ||= Operations::Command.new(
      ...,
      on_success: [
        PublishCommentUpdatedEvent.new,
        NotifyBoardAdmin.new
      ]
    )
  end
end

class PublishCommentUpdatedEvent
  def call(params, comment:, **)
    PublishEventJob.perform_later('comment', comment, params: params)
  end
end

class NotifyBoardAdmin
  def call(_, comment:, **)
    AdminMailer.comment_updated(comment.id)
  end
end
```

Additionally, a callback `call` method can receive the operation result instead of params and context. This enables powerful introspection for generic callbacks.

```ruby
class PublishCommentUpdatedEvent
  def call(operation_result)
    PublishEventJob.perform_later(
      'comment',
      operation_result.context[:comment],
      params: operation_result.params,
      operation_name: operation_result.operation.operation.class.name.underscore
    )
  end
end
```

### Idempotency checks

Idempotency checks are used to skip the operation body in certain conditions. It is very similar to preconditions but if the idempotency check fails - the operation will be successful anyway. This is useful in cases when we want to ensure that operation is not going to run for the second time even if it was called, and especially for idempotent consumer pattern implementation in event-driven systems.

Normally, we advise for idempotency checks not to use the same logic which would be used for preconditions, i.e. not to use application business state checks. Instead, it is worth implementing a separate mechanism like `ProcessedEvents` DB table.

Idempotency checks are running after policy checks but before preconditions.

```ruby
class Order::MarkAsCompleted
  def self.default
    @default ||= Operations::Command.new(
      new,
      contract: Order::MarkAsCompleted::Contract.new,
      policy: nil,
      idempotency: [Idempotency::ProcessedEvents.new],
      preconditions: [Order::RequireStatus.new(:processing)]
    )
  end
end

class Order::MarkAsCompleted::Contract < OperationContract
  params do
    # event_id is optional and the operation can be called without it, i.e. from the console.
    optional(:event_id).filled(Types::UUID)
    optional(:order_id).filled(:integer)
  end

  find :order
end

class Order::RequireStatus
  extend Dry::Initializer
  include Dry::Monads[:result]

  param :statuses, [Types::Symbol]

  def call(order:, **)
    return Failure(error: :invalid_status, tokens: { status: order.status }) unless order.status.in?(statuses)

    Success()
  end
end

class Idempotency::ProcessedEvents
  include Dry::Monads[:result]

  # Notice that, unlike preconditions, idempotency checks have params provided
  def call(params, **)
    return Success() unless params.key?(:event_id)
    # Assume that `ProcessedEvents` has a unique index on `event_id`
    ProcessedEvents.create!(event_id: params[:event_id])
    Success()
  rescue ActiveRecord::StatementInvalid
    Failure({})
  end
end
```

**Important:** contrary to the operation, idempotency checks require to return a hash in Failure monad. This hash will be merged into the resulting context. This is necessary for operations interrupted during idempotency checks to return the same result as at the first run.

It might be also worth defining 2 different operations that will be called in different circumstances to reduce human error:

```ruby
class Order::MarkAsCompleted
  def self.system
    @system ||= Operations::Command.new(
      new,
      contract: Order::MarkAsCompleted::SystemContract.new,
      policy: nil,
      preconditions: [Order::RequireStatus.new(:processing)]
    )
  end

  # We use `merge` method here to dry the code a bit.
  def self.kafka
    @kafka ||= system.merge(
      contract: Order::MarkAsCompleted::KafkaContract.new,
      idempotency: [Idempotency::ProcessedEvents.new],
    )
  end
end

class Order::MarkAsCompleted::SystemContract < OperationContract
  params do
    optional(:order_id).filled(:integer)
  end

  find :order
end

# All the params and rules are inherited
class Order::MarkAsCompleted::KafkaContract < Order::MarkAsCompleted::SystemContract
  params do
    required(:event_id).filled(Types::UUID)
  end
end
```

In this case, `Order::MarkAsCompleted.system.call(...)` will be used in, say, console, and `Order::MarkAsCompleted.kafka.call(...)` will be used on Kafka event consumption.

### Convenience helpers

`Operations::Convenience` is an optional module that contains helpers for simpler operation definitions. See module documentation for more details.

### Form objects

Form objects were refactored to be separate from Command. Please check [UPGRADING_FORMS.md](UPGRADING_FORMS.md) for more details.

While we normally recommend using frontend-backend separation, it is still possible to use this framework with Rails view helpers:

```ruby
class PostsController < ApplicationController
  def edit
    @post_update_form = Post::Update.default_form.build(params, current_user: current_user)

    respond_with @post_update_form
  end

  def update
    @post_update_form = Post::Update.default_form.persist(params, current_user: current_user)

    respond_with @post_update_form, location: edit_post_url(@post_update_form.operation_result.context[:post])
  end
end
```

Where the form class is defined this way:

```ruby
class Post::Update
  def self.default
    @default ||= Operations::Command.new(...)
  end

  def self.default_form
    @default_form ||= Operations::Form.new(default)
  end
end
```

Then, the form can be used as any other form object. Unfortunately, there is no way to figure out the correct route for the operation form object, so it have to be provided manually:

```erb
# views/posts/edit.html.erb
<%= form_for @post_update_form, url: post_url(@post_update_form.operation_result.context[:post]) do |f| %>
  <%= f.input :title %>
  <%= f.text_area :body %>
<% end %>
```

In cases when we need to populate the form data, it is possible to pass `form_hydrator:`:

```ruby
class Post::Update
  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      hydrators: [Post::Update::Hydrator.new]
    )
  end
end

class Post::Update::Hydrator
  def call(form_class, params, post:, **_context)
    value_attributes = form_class.attributes.keys - %i[post_id]
    value_attributes.index_with { |name| post.public_send(name) }
  end
end
```

The general idea here is to figure out attributes we have in the contract (those attributes are also defined automatically in a generated form class) and then fetch those attributes from the model and merge them with the params provided within the request.

Also, in the case of, say, [simple_form](https://github.com/heartcombo/simple_form), we need to provide additional attributes information, like data type. It is possible to do this with `model_map:` option:

```ruby
class Post::Update
  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      model_map: Post::Update::ModelMap.new,
      hydrators: [Post::Update::Hydrator.new]
    )
  end
end

class Post::Update::ModelMap
  MAPPING = {
    %w[published_at] => Post, # a model can be passed but beware of circular dependencies, better use strings
    %w[title] => "Post", # or a model name - safer option
    %w[content] => "Post#body" # referencing different attribute is possible, useful for naming migration or translations
  }.freeze

  def call(path)
    MAPPING[path] # returns the mapping for a single path
  end
end
```

In forms, params input is already transformed to extract the nested data with the form name. `form_for @post_update_form` will generate the form that send params nested under the `params[:post_update_form]` key. By default operation forms extract this form data and send it to the operation at the top level, so `{ id: 42, post_update_form: { title: "Post Title" } }` params will be sent to the operation as `{ id: 42, title: "Post Title" }`. Strong params are also accepted by the form, though they are being converted with `to_unsafe_hash`. Though the form name can be customized if necessary:

```ruby
class Post::Update
  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      model_name: "custom_post_update_form", # form name can be customized
    )
  end
end
```

It is possible to add more params transfomations to the form in cases when operation contract is different from the params structure:

```ruby
class Post::Update
  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      params_transformations: [
        ParamsMap.new(id: :post_id),
        NestedAttributes.new(:sections)
      ]
    )
  end

  contract do
    required(:post_id).filled(:integer)
    optional(:title).filled(:string)
    optional(:sections).array(:hash) do
      optional(:id).filled(:integer)
      optional(:content).filled(:string)
      optional(:_destroy).filled(:bool)
    end
  end
end

# This will transform `{ id: 42, title: "Post Title" }` params to `{ post_id: 42, title: "Post Title" }`
class ParamsMap
  extend Dry::Initializer

  param :params_map

  def call(_form_class, params, **_context)
    params.transform_keys { |key| params_map[key] || key }
  end
end

# And this will transform nested attributes hash from the form to an array acceptable by the operation:
# from
#   `{ id: 42, sections_attributes: { '0' => { id: 1, content: "First paragraph" }, 'new' => { content: 'New Paragraph' } } }`
# into
#   `{ id: 42, sections: [{ id: 1, content: "First paragraph" }, { content: 'New Paragraph' }] }`
class NestedAttributes
  extend Dry::Initializer

  param :name, Types::Coercible::Symbol

  def call(_form_class, params, **_context)
    params[name] = params[:"#{name}_attrbutes"].values
  end
end
```

By default, the top-level form objects instantiated from the form will have `persisted?` flag set to `true`. This will result the form to use the `PATCH` werb like for any persisted AR object. If it is required to generate a form with the `POST` verb in case of operation, say, creating some objects, this default behavior can be customised:

```ruby
class Post::Create
  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      persisted: false
    )
  end
end
```

Note that operation itself is agnostic to the persistence layer, so there is no way for it to figure out this semanticsa automatically.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/BookingSync/operations.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
