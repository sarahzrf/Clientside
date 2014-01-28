require 'sinatra'
require '../../lib/clientside'

class Printer
  include Clientside::Accessible
  js_allow :display

  def display(text)
    puts text
    self
  end

  def priv
    puts "You can't call this!"
  end
end

use Clientside::Middleware

p = Printer.new
get '/' do
  @p = p
  erb :printer
end

