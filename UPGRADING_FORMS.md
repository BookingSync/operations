# New form objects

In version 0.7.0, a new form objects system were introduced. The old way of using form objects is deprecated and will be removed in 1.0.0. In order to upgrade your code to start using the new way please follow the guide:

## Replace `Operations::Form` with `Operations::Form::Base`

If you have any classes that were inherited from `Operations::Form`, please change them to inherit from `Operations::Form::Base`

## Define forms as separate objects on top of the existing operations:

```ruby
# Before
class Post::Update
  def self.default
    @default ||= Operations::Command.new(
      ...,
      form_hydrator: Post::Update::Hydrator.new,
      form_model_map: {
        [%r{.+}] => "Post"
      }
    )
  end
end

# After
class Post::Update
  def self.default
    @default ||= Operations::Command.new(...)
  end

  def self.default_form
    @default_form ||= Operations::Form.new(
      default,
      hydrator: Post::Update::Hydrator.new,
      model_map: Post::Update::ModelMap.new,
      params_transformations: [
        ParamsMap.new(id: :post_id)
      ]
    )
  end
end
```

Where `Post::Update::ModelMap` can be a copy of [Operations::Form::DeprecatedLegacyModelMapImplementation](https://github.com/BookingSync/operations/blob/main/lib/operations/form/deprecated_legacy_model_map_implementation.rb) or your own implementation.

And `ParamsMap` can be as simple as:

```ruby
class ParamsMap
  extend Dry::Initializer

  param :params_map

  def call(_form_class, params, **_context)
    params.transform_keys { |key| params_map[key] || key }
  end
end
```

## Change the way you use forms in you controllers and views:

```ruby
# Before
class PostsController < ApplicationController
  def edit
    @post_update = Post::Update.default.callable(
      { post_id: params[:id] },
      current_user: current_user
    )

    respond_with @post_update
  end

  def update
    # With operations we don't need strong parameters as the operation contract takes care of this.
    @post_update = Post::Update.default.call(
      { **params[:post_update_default_form], post_id: params[:id] },
      current_user: current_user
    )

    respond_with @post_update, location: edit_post_url(@post_update.context[:post])
  end
end

# After
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

Notice that `callable` and `call` methond are replaced with `build` and `persist` respectively.
