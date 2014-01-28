Clientside
==========

A simple Rack middleware and JavaScript generator for basic remote method invocation over websockets.

##Installation

    sudo gem install clientside

##Usage

In your class:

    include Clientside::Accessible
    js_allow :methods, :available, :from, :js

In your app:

    use Clientside::Middleware

In your `<head>`:

    <%= Clientside.embed jsVarName: ruby_object, anotherJS: another_ruby %>

In your JS:

    varNameFromEmbed.method_on_server_object("foo", 3) // => promise object

