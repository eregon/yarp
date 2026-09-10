# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  class ParseResult < Result
    # The :line tracepoint event gets fired whenever the Ruby VM encounters an
    # expression on a new line. The types of expressions that can trigger this
    # event are:
    #
    # * if statements
    # * unless statements
    # * nodes that are children of statements lists
    #
    # In order to keep track of the newlines, we have a list of offsets that
    # come back from the parser. We assign these offsets to the first nodes that
    # we find in the tree that are on those lines.
    #
    # Note that the logic in this file should be kept in sync with the Java
    # MarkNewlinesVisitor, since that visitor is responsible for marking the
    # newlines for JRuby/TruffleRuby.
    #
    # This file is autoloaded only when `mark_newlines!` is called, so the
    # re-opening of the various nodes in this file will only be performed in
    # that case. We do that to avoid storing the extra `@newline` instance
    # variable on every node if we don't need it.
    class Newlines < Visitor
      # The map of lines indices to whether or not they have been marked as
      # emitting a newline event.
      # @rbs @lines: Array[bool]

      # Create a new Newlines visitor with the given newline offsets.
      #
      #: (Integer lines) -> void
      def initialize(lines)
        @lines = Array.new(1 + lines, false)
        @suppressed = nil
      end

      # Permit block nodes to mark newlines within themselves.
      #
      #: (BlockNode node) -> void
      def visit_block_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # Permit lambda nodes to mark newlines within themselves.
      #
      #: (LambdaNode node) -> void
      def visit_lambda_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # Permit def nodes to mark newlines within themselves. The body of an
      # endless method definition never emits newline events, so in that case
      # mark every line as already seen while visiting it instead. Nested
      # scopes (blocks, lambdas, etc.) reset the lines and emit events again.
      #
      #: (DefNode node) -> void
      def visit_def_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, !node.equal_loc.nil?)

        # A bare `nil` in the method's tail (value) position is the implicit
        # `nil` return, which does not emit a newline event. Collect those nil
        # nodes so they can be skipped while visiting the body.
        old_suppressed = @suppressed
        @suppressed = {} #: Hash[Integer, bool]
        suppress_tail_nils(node.body)

        begin
          super(node)
        ensure
          @lines = old_lines
          @suppressed = old_suppressed
        end
      end

      # Permit class nodes to mark newlines within themselves.
      #
      #: (ClassNode node) -> void
      def visit_class_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # Permit module nodes to mark newlines within themselves.
      #
      #: (ModuleNode node) -> void
      def visit_module_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # Permit singleton class nodes to mark newlines within themselves.
      #
      #: (SingletonClassNode node) -> void
      def visit_singleton_class_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # Statements inside string interpolation do not emit newline events, so
      # mark every line as already seen while visiting them. Nested scopes
      # (blocks, lambdas, defs, etc.) reset the lines and emit events again.
      #
      #: (EmbeddedStatementsNode node) -> void
      def visit_embedded_statements_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, true)

        begin
          super(node)
        ensure
          @lines = old_lines
        end
      end

      # The predicate of a while loop is compiled at the end of the loop,
      # after the body, so any statements it contains (from parentheses)
      # emit their line events again even if the lines were already seen.
      #
      #: (WhileNode node) -> void
      def visit_while_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          visit(node.predicate)
        ensure
          @lines = old_lines
        end

        visit(node.statements)
      end

      # The predicate of an until loop is compiled at the end of the loop,
      # after the body, so any statements it contains (from parentheses)
      # emit their line events again even if the lines were already seen.
      #
      #: (UntilNode node) -> void
      def visit_until_node(node)
        old_lines = @lines
        @lines = Array.new(old_lines.size, false)

        begin
          visit(node.predicate)
        ensure
          @lines = old_lines
        end

        visit(node.statements)
      end

      # Mark if nodes as newlines.
      #
      #: (IfNode node) -> void
      def visit_if_node(node)
        node.newline_flag!(@lines)
        super(node)
      end

      # Mark unless nodes as newlines.
      #
      #: (UnlessNode node) -> void
      def visit_unless_node(node)
        node.newline_flag!(@lines)
        super(node)
      end

      # Permit statements lists to mark newlines within themselves.
      #
      #: (StatementsNode node) -> void
      def visit_statements_node(node)
        node.body.each do |child|
          next if @suppressed&.include?(child.node_id) && child.is_a?(NilNode)
          child.newline_flag!(@lines)
        end
        super(node)
      end

      private

      # Walk the tail (value) positions of a method body and record any bare
      # nil found there, recursing through the branches of conditionals that
      # are themselves in tail position. These are the method's implicit nil
      # return, which does not emit a newline event.
      #
      #: (Prism::node? node) -> void
      def suppress_tail_nils(node)
        case node
        when NilNode
          @suppressed[node.node_id] = true
        when StatementsNode
          suppress_tail_nils(node.body.last)
        when ParenthesesNode
          suppress_tail_nils(node.body)
        when IfNode
          suppress_tail_nils(node.statements)
          suppress_tail_nils(node.subsequent)
        when UnlessNode
          suppress_tail_nils(node.statements)
          suppress_tail_nils(node.else_clause)
        when ElseNode
          suppress_tail_nils(node.statements)
        when CaseNode
          node.conditions.each do |condition|
            suppress_tail_nils(condition.statements) if condition.is_a?(WhenNode)
          end
          suppress_tail_nils(node.else_clause)
        end
      end
    end
  end

  class Node
    # Tracks whether or not this node should emit a newline event when the
    # instructions that it represents are executed.
    # @rbs @newline_flag: bool

    #: () -> bool
    def newline_flag? # :nodoc:
      !!defined?(@newline_flag)
    end

    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      line = location.start_line
      unless lines[line]
        lines[line] = true
        @newline_flag = true
      end
    end
  end

  class BeginNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      # Never mark BeginNode with a newline flag, mark children instead.
    end
  end

  class ParenthesesNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      # Never mark ParenthesesNode with a newline flag, mark children instead.
    end
  end

  class IfNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      predicate.newline_flag!(lines)
    end
  end

  class UnlessNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      predicate.newline_flag!(lines)
    end
  end

  class UntilNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      if location.start_offset == keyword_loc.start_offset && predicate.is_a?(ParenthesesNode)
        # A parenthesized predicate emits its own line event when it is
        # compiled at the end of the loop, in addition to this one.
        super
      else
        predicate.newline_flag!(lines)
      end
    end
  end

  class WhileNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      if location.start_offset == keyword_loc.start_offset && predicate.is_a?(ParenthesesNode)
        # A parenthesized predicate emits its own line event when it is
        # compiled at the end of the loop, in addition to this one.
        super
      else
        predicate.newline_flag!(lines)
      end
    end
  end

  class RescueModifierNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      expression.newline_flag!(lines)
    end
  end

  # The line event for a statement is emitted where its first instruction is
  # compiled, so nodes whose first instruction comes from a sub-expression
  # delegate their newline flag to that sub-expression: assignments to their
  # value, calls to their receiver, and array, hash, and interpolated string
  # literals to their first element. Static literals are the exception: they
  # are compiled to a single instruction on the first line of the literal, so
  # they do not delegate.

  class LocalVariableWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class InstanceVariableWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class ClassVariableWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class GlobalVariableWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class ConstantWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class ConstantPathWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class MultiWriteNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      value.newline_flag!(lines)
    end
  end

  class CallNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      if (receiver = self.receiver)
        receiver.newline_flag!(lines)
      else
        super
      end
    end
  end

  class ArrayNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = elements.first
      if first && !static_literal?
        first.newline_flag!(lines)
      else
        super
      end
    end
  end

  class HashNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = elements.first
      if first && !static_literal?
        first.newline_flag!(lines)
      else
        super
      end
    end
  end


  class InterpolatedMatchLastLineNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = parts.first
      first.newline_flag!(lines) if first
    end
  end

  class InterpolatedRegularExpressionNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = parts.first
      first.newline_flag!(lines) if first
    end
  end

  class InterpolatedStringNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = parts.first
      if first && !static_literal?
        first.newline_flag!(lines)
      else
        super
      end
    end
  end

  class InterpolatedSymbolNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = parts.first
      first.newline_flag!(lines) if first
    end
  end

  class InterpolatedXStringNode < Node
    #: (Array[bool] lines) -> void
    def newline_flag!(lines) # :nodoc:
      first = parts.first
      first.newline_flag!(lines) if first
    end
  end
end
