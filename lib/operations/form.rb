# frozen_string_literal: true

# Configures and defines a form object factory.
class Operations::Form
  # We need to make deprecated inheritance from Operations::Form act exactly the
  # same way as from Operations::Form::Base. In order to do this, we are encapsulating all the
  # inheritable functionality in 2 modules and removing methods defined in Operations::Form
  # from the result class.
  def self.inherited(subclass)
    super

    return unless self == Operations::Form

    ActiveSupport::Deprecation.new.warn("Inheritance from Operations::Form is deprecated and will be " \
      "removed in 1.0.0. Please inherit from Operations::Form::Base instead")

    (Operations::Form.instance_methods - Object.instance_methods).each do |method|
      subclass.undef_method(method)
    end

    subclass.extend Operations::Form::Base::ClassMethods
    subclass.include Operations::Form::Base::InstanceMethods
  end
end
