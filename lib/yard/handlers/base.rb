module YARD
  module Handlers
    # Raise this error when a handler should exit before completing.
    # The exception will be silenced, allowing the next handler(s) in the
    # queue to be executed.
    # @since 0.8.4
    class HandlerAborted < ::RuntimeError; end

    # Raised during processing phase when a handler needs to perform
    # an operation on an object's namespace but the namespace could
    # not be resolved.
    class NamespaceMissingError < Parser::UndocumentableError
      # The object the error occurred on
      # @return [CodeObjects::Base] a code object
      attr_accessor :object

      def initialize(object) @object = object end
    end

    # Handlers are pluggable semantic parsers for YARD's code generation
    # phase. They allow developers to control what information gets
    # generated by YARD, giving them the ability to, for instance, document
    # any Ruby DSLs that a customized framework may use. A good example
    # of this would be the ability to document and generate meta data for
    # the 'describe' declaration of the RSpec testing framework by simply
    # adding a handler for such a keyword. Similarly, any Ruby API that
    # takes advantage of class level declarations could add these to the
    # documentation in a very explicit format by treating them as first-
    # class objects in any outputted documentation.
    #
    # == Overview of a Typical Handler Scenario
    #
    # Generally, a handler class will declare a set of statements which
    # it will handle using the {handles} class declaration. It will then
    # implement the {#process} method to do the work. The processing would
    # usually involve the manipulation of the {#namespace}, {#owner}
    # {CodeObjects::Base code objects} or the creation of new ones, in
    # which case they should be registered by {#register}, a method that
    # sets some basic attributes for the new objects.
    #
    # Handlers are usually simple and take up to a page of code to process
    # and register a new object or add new attributes to the current +namespace+.
    #
    # == Setting up a Handler for Use
    #
    # A Handler is automatically registered when it is subclassed from the
    # base class. The only other thing that needs to be done is to specify
    # which statement the handler will process. This is done with the +handles+
    # declaration, taking either a {Parser::Ruby::Legacy::RubyToken}, {String} or `Regexp`.
    # Here is a simple example which processes module statements.
    #
    #   class MyModuleHandler < YARD::Handlers::Base
    #     handles TkMODULE
    #
    #     def process
    #       # do something
    #     end
    #   end
    #
    # == Processing Handler Data
    #
    # The goal of a specific handler is really up to the developer, and as
    # such there is no real guideline on how to process the data. However,
    # it is important to know where the data is coming from to be able to use
    # it.
    #
    # === +statement+ Attribute
    #
    # The +statement+ attribute pertains to the {Parser::Ruby::Legacy::Statement} object
    # containing a set of tokens parsed in by the parser. This is the main set
    # of data to be analyzed and processed. The comments attached to the statement
    # can be accessed by the {Parser::Ruby::Legacy::Statement#comments} method, but generally
    # the data to be processed will live in the +tokens+ attribute. This list
    # can be converted to a +String+ using +#to_s+ to parse the data with
    # regular expressions (or other text processing mechanisms), if needed.
    #
    # === +namespace+ Attribute
    #
    # The +namespace+ attribute is a {CodeObjects::NamespaceObject namespace object}
    # which represents the current namespace that the parser is in. For instance:
    #
    #   module SomeModule
    #     class MyClass
    #       def mymethod; end
    #     end
    #   end
    #
    # If a handler was to parse the 'class MyClass' statement, it would
    # be necessary to know that it belonged inside the SomeModule module.
    # This is the value that +namespace+ would return when processing such
    # a statement. If the class was then entered and another handler was
    # called on the method, the +namespace+ would be set to the 'MyClass'
    # code object.
    #
    # === +owner+ Attribute
    #
    # The +owner+ attribute is similar to the +namespace+ attribute in that
    # it also follows the scope of the code during parsing. However, a namespace
    # object is loosely defined as a module or class and YARD has the ability
    # to parse beyond module and class blocks (inside methods, for instance),
    # so the +owner+ attribute would not be limited to modules and classes.
    #
    # To put this into context, the example from above will be used. If a method
    # handler was added to the mix and decided to parse inside the method body,
    # the +owner+ would be set to the method object but the namespace would remain
    # set to the class. This would allow the developer to process any method
    # definitions set inside a method (def x; def y; 2 end end) by adding them
    # to the correct namespace (the class, not the method).
    #
    # In summary, the distinction between +namespace+ and +owner+ can be thought
    # of as the difference between first-class Ruby objects (namespaces) and
    # second-class Ruby objects (methods).
    #
    # === +visibility+ and +scope+ Attributes
    #
    # Mainly needed for parsing methods, the +visibility+ and +scope+ attributes
    # refer to the public/protected/private and class/instance values (respectively)
    # of the current parsing position.
    #
    # == Parsing Blocks in Statements
    #
    # In addition to parsing a statement and creating new objects, some
    # handlers may wish to continue parsing the code inside the statement's
    # block (if there is one). In this context, a block means the inside
    # of any statement, be it class definition, module definition, if
    # statement or classic 'Ruby block'.
    #
    # For example, a class statement would be "class MyClass" and the block
    # would be a list of statements including the method definitions inside
    # the class. For a class handler, the programmer would execute the
    # {#parse_block} method to continue parsing code inside the block, with
    # the +namespace+ now pointing to the class object the handler created.
    #
    # YARD has the ability to continue into any block: class, module, method,
    # even if statements. For this reason, the block parsing method must be
    # invoked explicitly out of efficiency sake.
    #
    # @abstract Subclass this class to provide a handler for YARD to use
    #   during the processing phase.
    #
    # @see CodeObjects::Base
    # @see CodeObjects::NamespaceObject
    # @see handles
    # @see #namespace
    # @see #owner
    # @see #register
    # @see #parse_block
    class Base
      # For accessing convenience, eg. "MethodObject"
      # instead of the full qualified namespace
      include YARD::CodeObjects

      include Parser

      class << self
        # Clear all registered subclasses. Testing purposes only
        # @return [void]
        def clear_subclasses
          @@subclasses = []
        end

        # Returns all registered handler subclasses.
        # @return [Array<Base>] a list of handlers
        def subclasses
          @@subclasses ||= []
        end

        def inherited(subclass)
          @@subclasses ||= []
          @@subclasses << subclass
        end

        # Declares the statement type which will be processed
        # by this handler.
        #
        # A match need not be unique to a handler. Multiple
        # handlers can process the same statement. However,
        # in this case, care should be taken to make sure that
        # {#parse_block} would only be executed by one of
        # the handlers, otherwise the same code will be parsed
        # multiple times and slow YARD down.
        #
        # @param [Parser::RubyToken, Symbol, String, Regexp] matches
        #   statements that match the declaration will be
        #   processed by this handler. A {String} match is
        #   equivalent to a +/\Astring/+ regular expression
        #   (match from the beginning of the line), and all
        #   token matches match only the first token of the
        #   statement.
        #
        def handles(*matches)
          (@handlers ||= []).concat(matches)
        end

        # This class is implemented by {Ruby::Base} and {Ruby::Legacy::Base}.
        # To implement a base handler class for another language, implement
        # this method to return true if the handler should process the given
        # statement object. Use {handlers} to enumerate the matchers declared
        # for the handler class.
        #
        # @param statement a statement object or node (depends on language type)
        # @return [Boolean] whether or not this handler object should process
        #   the given statement
        def handles?(statement) # rubocop:disable Lint/UnusedMethodArgument
          raise NotImplementedError, "override #handles? in a subclass"
        end

        # @return [Array] a list of matchers for the handler object.
        # @see handles?
        def handlers
          @handlers ||= []
        end

        # Declares that the handler should only be called when inside a
        # {CodeObjects::NamespaceObject}, not a method body.
        #
        # @return [void]
        def namespace_only
          @namespace_only = true
        end

        # @return [Boolean] whether the handler should only be processed inside
        #   a namespace.
        def namespace_only?
          (@namespace_only ||= false) ? true : false
        end

        # Declares that a handler should only be called when inside a filename
        # by its basename or a regex match for the full path.
        #
        # @param [String, Regexp] filename a matching filename or regex
        # @return [void]
        # @since 0.6.2
        def in_file(filename)
          (@in_files ||= []) << filename
        end

        # @return [Boolean] whether the filename matches the declared file
        #   match for a handler. If no file match is specified, returns true.
        # @since 0.6.2
        def matches_file?(filename)
          @in_files ||= nil # avoid ruby warnings
          return true unless @in_files
          @in_files.any? do |in_file|
            case in_file
            when String
              File.basename(filename) == in_file
            when Regexp
              filename =~ in_file
            else
              true
            end
          end
        end

        # Generates a +process+ method, equivalent to +def process; ... end+.
        # Blocks defined with this syntax will be wrapped inside an anonymous
        # module so that the handler class can be extended with mixins that
        # override the +process+ method without alias chaining.
        #
        # @!macro yard.handlers.process
        #   @!method process
        #   Main processing callback
        #   @return [void]
        # @see #process
        # @return [void]
        # @since 0.5.4
        def process(&block)
          mod = Module.new
          mod.send(:define_method, :process, &block)
          include mod
        end
      end

      def initialize(source_parser, stmt)
        @parser = source_parser
        @statement = stmt
      end

      # The main handler method called by the parser on a statement
      # that matches the {handles} declaration.
      #
      # Subclasses should override this method to provide the handling
      # functionality for the class.
      #
      # @return [Array<CodeObjects::Base>, CodeObjects::Base, Object]
      #   If this method returns a code object (or a list of them),
      #   they are passed to the +#register+ method which adds basic
      #   attributes. It is not necessary to return any objects and in
      #   some cases you may want to explicitly avoid the returning of
      #   any objects for post-processing by the register method.
      #
      # @see handles
      # @see #register
      #
      def process
        raise NotImplementedError, "#{self} did not implement a #process method for handling."
      end

      # Parses the semantic "block" contained in the statement node.
      #
      # @abstract Subclasses should call {Processor#process parser.process}
      def parse_block(*)
        raise NotImplementedError, "#{self} did not implement a #parse_block method for handling"
      end

      # @return [Processor] the processor object that manages all global state
      #   during handling.
      attr_reader :parser

      # @return [Object] the statement object currently being processed. Usually
      #   refers to one semantic language statement, though the strict definition
      #   depends on the parser used.
      attr_reader :statement

      # (see Processor#owner)
      attr_accessor :owner

      # (see Processor#namespace)
      attr_accessor :namespace

      # (see Processor#visibility)
      attr_accessor :visibility

      # (see Processor#scope)
      attr_accessor :scope

      # (see Processor#globals)
      attr_reader :globals

      # (see Processor#extra_state)
      attr_reader :extra_state

      undef owner, owner=, namespace, namespace=
      undef visibility, visibility=, scope, scope=
      undef globals, extra_state

      def owner; parser.owner end
      def owner=(v) parser.owner = v end
      def namespace; parser.namespace end
      def namespace=(v); parser.namespace = v end
      def visibility; parser.visibility end
      def visibility=(v); parser.visibility = v end
      def scope; parser.scope end
      def scope=(v); parser.scope = v end
      def globals; parser.globals end
      def extra_state; parser.extra_state end

      # Aborts a handler by raising {Handlers::HandlerAborted}.
      # An exception will only be logged in debugging mode for
      # this kind of handler exit.
      #
      # @since 0.8.4
      def abort!
        raise Handlers::HandlerAborted
      end

      # Executes a given block with specific state values for {#owner},
      # {#namespace} and {#scope}.
      #
      # @option opts [CodeObjects::NamespaceObject] :namespace (value of #namespace)
      #   the namespace object that {#namespace} will be equal to for the
      #   duration of the block.
      # @option opts [Symbol] :scope (:instance)
      #   the scope for the duration of the block.
      # @option opts [CodeObjects::Base] :owner (value of #owner)
      #   the owner object (method) for the duration of the block
      # @yield a block to execute with the given state values.
      def push_state(opts = {})
        opts = {
          :namespace => namespace,
          :scope => :instance,
          :owner => owner || namespace,
          :visibility => nil
        }.update(opts)

        ns, vis, sc, oo = namespace, visibility, scope, owner
        self.namespace = opts[:namespace]
        self.visibility = opts[:visibility] || :public
        self.scope = opts[:scope]
        self.owner = opts[:owner]

        yield

        self.namespace = ns
        self.visibility = vis
        self.scope = sc
        self.owner = oo
      end

      # Do some post processing on a list of code objects.
      # Adds basic attributes to the list of objects like
      # the filename, line number, {CodeObjects::Base#dynamic},
      # source code and {CodeObjects::Base#docstring},
      # but only if they don't exist.
      #
      # @param [Array<CodeObjects::Base>] objects
      #   the list of objects to post-process.
      #
      # @return [CodeObjects::Base, Array<CodeObjects::Base>]
      #   returns whatever is passed in, for chainability.
      #
      def register(*objects)
        objects.flatten.each do |object|
          next unless object.is_a?(CodeObjects::Base)
          register_ensure_loaded(object)
          yield(object) if block_given?
          register_file_info(object)
          register_source(object)
          register_visibility(object)
          register_docstring(object)
          register_group(object)
          register_dynamic(object)
          register_module_function(object)
        end
        objects.size == 1 ? objects.first : objects
      end

      # Ensures that the object's namespace is loaded before attaching it
      # to the namespace.
      #
      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_ensure_loaded(object)
        ensure_loaded!(object.namespace)
        object.namespace.children << object
      rescue NamespaceMissingError
      end

      # Registers the file/line of the declaration with the object
      #
      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_file_info(object, file = parser.file, line = statement.line, comments = statement.comments)
        object.add_file(file, line, comments)
      end

      # Registers any docstring found for the object and expands macros
      #
      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_docstring(object, docstring = statement.comments, stmt = statement)
        docstring = docstring.join("\n") if Array === docstring
        parser = Docstring.parser
        parser.parse(docstring || "", object, self)

        if object && docstring
          object.docstring = parser.to_docstring

          # Add hash_flag/line_range
          if stmt
            object.docstring.hash_flag = stmt.comments_hash_flag
            object.docstring.line_range = stmt.comments_range
          end
        end

        register_transitive_tags(object)
      end

      # Registers the object as being inside a specific group
      #
      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_group(object, group = extra_state.group)
        if group
          unless object.namespace.is_a?(Proxy)
            object.namespace.groups |= [group]
          end
          object.group = group
        end
      end

      # Registers any transitive tags from the namespace on the object
      #
      # @param [CodeObjects::Base, nil] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_transitive_tags(object)
        return unless object && !object.namespace.is_a?(Proxy)
        Tags::Library.transitive_tags.each do |tag|
          next unless object.namespace.has_tag?(tag)
          next if object.has_tag?(tag)
          object.add_tag(*object.namespace.tags(tag))
        end
      end

      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_source(object, source = statement, type = parser.parser_type)
        return unless object.is_a?(MethodObject)
        object.source ||= source
        object.source_type = type
      end

      # Registers visibility on a method object. If the object does not
      # respond to setting visibility, nothing is done.
      #
      # @param [#visibility=] object the object to register
      # @param [Symbol] visibility the visibility to set on the object
      # @since 0.8.0
      def register_visibility(object, visibility = self.visibility)
        return unless object.respond_to?(:visibility=)
        return if object.is_a?(NamespaceObject)
        object.visibility = visibility
      end

      # Registers the same method information on the module function, if
      # the object was defined as a module function.
      #
      # @param [CodeObjects::Base] object the possible module function object
      #   to copy data for
      # @since 0.8.0
      def register_module_function(object)
        return unless object.is_a?(MethodObject)
        return unless object.module_function?
        modobj = MethodObject.new(object.namespace, object.name)
        object.copy_to(modobj)
        modobj.visibility = :private # rubocop:disable Lint/UselessSetterCall
      end

      # Registers the object as dynamic if the object is defined inside
      # a method or block (owner != namespace)
      #
      # @param [CodeObjects::Base] object the object to register
      # @return [void]
      # @since 0.8.0
      def register_dynamic(object)
        object.dynamic = true if owner != namespace
      end

      # Ensures that a specific +object+ has been parsed and loaded into the
      # registry. This is necessary when adding data to a namespace, for instance,
      # since the namespace may not have been processed yet (it can be located
      # in a file that has not been handled).
      #
      # Calling this method defers the handler until all other files have been
      # processed. If the object gets resolved, the rest of the handler continues,
      # otherwise an exception is raised.
      #
      # @example Adding a mixin to the String class programmatically
      #   ensure_loaded! P('String')
      #   # "String" is now guaranteed to be loaded
      #   P('String').mixins << P('MyMixin')
      #
      # @param [Proxy, CodeObjects::Base] object the object to resolve.
      # @param [Integer] max_retries the number of times to defer the handler
      #   before raising a +NamespaceMissingError+.
      # @raise [NamespaceMissingError] if the object is not resolved within
      #   +max_retries+ attempts, this exception is raised and the handler
      #   finishes processing.
      def ensure_loaded!(object, max_retries = 1)
        return if object.root?
        return object unless object.is_a?(Proxy)

        retries = 0
        while object.is_a?(Proxy)
          if retries <= max_retries
            log.debug "Missing object #{object} in file `#{parser.file}', moving it to the back of the line."
            parser.parse_remaining_files
          else
            raise NamespaceMissingError, object
          end
          retries += 1
        end
        object
      end

      # @group Macro Support

      # @abstract Implement this method to return the parameters in a method call
      #   statement. It should return an empty list if the statement is not a
      #   method call.
      # @return [Array<String>] a list of argument names
      def call_params
        raise NotImplementedError
      end

      # @abstract Implement this method to return the method being called in
      #   a method call. It should return nil if the statement is not a method
      #   call.
      # @return [String] the method name being called
      # @return [nil] if the statement is not a method call
      def caller_method
        raise NotImplementedError
      end
    end
  end
end
