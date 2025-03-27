# frozen_string_literal: true

module TestHelpers
  def normalize_inspect(string)
    string
      .gsub(%r{Proc:0x[^>]+}, "Proc:0x")
      .gsub(%r{Class:0x[^>]+}, "Class:0x")
      .gsub(%r{:(\w+)=>\n}, "\\1:\n")
      .gsub(%r{:(\w+)=>}, '\1: ')
  end
end
