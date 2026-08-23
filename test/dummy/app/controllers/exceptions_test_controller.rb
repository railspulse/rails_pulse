class ExceptionsTestController < ApplicationController
  EXCEPTION_TYPES = {
    "record_not_found"      => -> { raise ActiveRecord::RecordNotFound, "Couldn't find Post with 'id'=99999" },
    "zero_division"         => -> { 1 / 0 },
    "argument_error"        => -> { raise ArgumentError, "wrong number of arguments (given 3, expected 1)" },
    "runtime_error"         => -> { raise RuntimeError, "something went wrong in the application" },
    "name_error"            => -> { raise NameError, "undefined local variable or method 'undefined_var'" },
    "type_error"            => -> { raise TypeError, "no implicit conversion of nil into String" },
    "key_error"             => -> { raise KeyError, "key not found: :missing_key" },
    "not_implemented"       => -> { raise NotImplementedError, "This feature is not yet implemented" }
  }.freeze

  def index
  end

  def raise_exception
    type = params[:type].to_s
    handler = EXCEPTION_TYPES[type]

    unless handler
      redirect_to exceptions_test_path, alert: "Unknown exception type: #{type}"
      return
    end

    handler.call
  end
end
