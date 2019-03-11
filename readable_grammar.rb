require 'json'
require 'yaml'

# TODO
    # use the turnOffNumberedCaptureGroups to disable manual regex groups (which otherwise would completely break the group attributes)
    # rename "name" to "tag_as", and process "include" as a list of symbols (to global_name) and other patterns
    # make the hash-options come before the pattern
    # check for making a copy of the pattern and mutating/overriding it
    # add the global register functionality
    # add method to append something to all tag names (add an extension: "blah" argument to "to_tag")


def turnOffNumberedCaptureGroups(regex)
    # unescaped ('s can exist in character classes, and character class-style code can exist inside comments.
    # this removes the comments, then finds the character classes: escapes the ('s inside the character classes then 
    # reverse the string so that varaible-length lookaheads can be used instead of fixed length lookbehinds
    as_string_reverse = regex.to_s.reverse
    no_preceding_escape = /(?=(?:(?:\\\\)*)(?:[^\\]|\z))/
    reverse_character_class_match = /(\]#{no_preceding_escape}[\s\S]*?\[#{no_preceding_escape})/
    reverse_comment_match = /(\)#{no_preceding_escape}[^\)]*#\?\(#{no_preceding_escape})/
    reverse_start_paraenthese_match = /\(#{no_preceding_escape}/
    reverse_capture_group_start_paraenthese_match = /(?<!\?)\(#{no_preceding_escape}/
    
    reversed_but_fixed = as_string_reverse.gsub(/#{reverse_character_class_match}|#{reverse_comment_match}/) do |match_data, more_data|
        # if found a comment, just remove it
        if (match_data.size > 3) and  match_data[-3..-1] == '#?('
            ''
        # if found a character class, then escape any ()'s that are in it
        else
            match_data.gsub reverse_start_paraenthese_match, '\\('.reverse
        end
    end
    # make all capture groups non-capture groups
    reversed_but_fixed.gsub! reverse_capture_group_start_paraenthese_match, '(?:'.reverse
    return Regexp.new(reversed_but_fixed.reverse)
end

# extend Regexp to make expressions very readable
class Regexp
    attr_accessor :global_name
    def to_tag
        output = {
            match: self.removeDefaultModeModifiers,
            captures: {}
        }
        
        # TODO, if this pattern has a :global_name then just return { include: #global_name }
        
        for group_number in 1..@group_attributes.size
            raw_attributes = @group_attributes[group_number - 1]
            
            # by default carry everything over
            output[:captures][group_number.to_s] = raw_attributes
            # convert "tag_as" into the TextMate "name"
            if raw_attributes[:tag_as] != nil
                output[:captures][group_number.to_s][:name] = raw_attributes[:tag_as]
                # remove it from the hash
                raw_attributes.delete(:tag_as)
            end
            
            # check for "includes"
            if raw_attributes[:includes] != nil
                if not (raw_attributes[:includes].instance_of? Array)
                    raise "\n\nWhen converting a pattern into a tag (to_tag) there was a group that had an 'includes', but the includes wasn't an array\nThe pattern is:#{self}\nThe group attributes are: #{raw_attributes}"
                end
                # create the pattern list
                output[:captures][group_number.to_s][:patterns] = []
                for each_include in raw_attributes[:includes]
                    # if its a string then include it directly
                    if (each_include.is_a? String)
                        output[:captures][group_number.to_s][:patterns].push({ include: each_include })
                    # if its a symbol then include a # to make it a global_name reference
                    elsif (each_include.is_a? Symbol)
                        output[:captures][group_number.to_s][:patterns].push({ include: "##{each_include}" })
                    # if its a pattern, then just include it
                    elsif (each_include.is_a? Regexp)
                        output[:captures][group_number.to_s][:patterns].push(each_include.to_tag)
                    end
                end
                # remove includes from the hash
                raw_attributes.delete(:includes)
            end
            # TODO add a check for :name, and :patterns and tell them to use tag_as and includes instead
            # add any other attributes
            output[:captures][group_number.to_s].merge(raw_attributes)
        end
        return output
    end
    def group_attributes
        if @group_attributes == nil
            @group_attributes = []
        end
        return @group_attributes
    end
    def updateGroupAttributes(previous_regex, next_regex, attributes)
        # TODO, initialize global_name: whenever there is a global_name inside the attributes, add the pattern to the global grammar object
        # TODO, check if next_regex is a Ranged pattern (in which case this should fail)
        @group_attributes = previous_regex.group_attributes + [ attributes ] + next_regex.group_attributes
        return self
    end
    # convert it to a string and have it without the "(?-mix )" part
    def removeDefaultModeModifiers()
        as_string = self.to_s
        # if it is the default settings (AKA -mix) then remove it
        if (as_string.size > 6) and (as_string[0..5] == '(?-mix')
            return as_string.sub(/\A\(\?\-mix\:/, "").sub(/\)\z/,"")
        else 
            return as_string
        end
    end
    # an alias operator for "removeDefaultModeModifiers"
    def -@()
        return self.removeDefaultModeModifiers
    end
    # 
    # English Helpers
    # 
    def or(other_regex, attributes={})
        return /(?:(?:(#{self.removeDefaultModeModifiers}|#{other_regex.removeDefaultModeModifiers})))/.updateGroupAttributes(self, other_regex, attributes)
    end
    def and(other_regex, attributes={})
        return /(#{self.removeDefaultModeModifiers}#{other_regex.removeDefaultModeModifiers})/.updateGroupAttributes(self, other_regex, attributes)
    end
    def then(other_regex, attributes={})
        return self.and(other_regex)
    end
    def lookAheadFor(other_regex)
        return /#{self.removeDefaultModeModifiers}(?=#{other_regex.removeDefaultModeModifiers})/
    end
    def lookAheadToAvoid(other_regex)
        return /#{self.removeDefaultModeModifiers}(?!#{other_regex.removeDefaultModeModifiers})/
    end
    def lookBehindFor(other_regex)
        return /#{self.removeDefaultModeModifiers}(?<=#{other_regex.removeDefaultModeModifiers})/
    end
    def lookBehindToAvoid(other_regex)
        return /#{self.removeDefaultModeModifiers}(?<!#{other_regex.removeDefaultModeModifiers})/
    end
    def thenNewPattern(other_regex, attributes={})
        return /#{self.removeDefaultModeModifiers}(#{other_regex.removeDefaultModeModifiers})/.updateGroupAttributes(self, other_regex, attributes)
    end
    def maybe(other_regex, attributes={})
        regex_as_string = other_regex.removeDefaultModeModifiers
        output_pattern = nil
        # if its already a + character
        if (regex_as_string.size == 3) and regex_as_string[0] == "\\" and regex_as_string[-1] == "+"
            output_pattern = /#{self.removeDefaultModeModifiers}#{regex_as_string[0] + regex_as_string[1]}*/
        elsif (regex_as_string.size == 2) and regex_as_string[0] != "\\" and regex_as_string[-1] == "+"
            output_pattern = /#{self.removeDefaultModeModifiers}#{regex_as_string[0]}*/
        else
            output_pattern = /#{self.removeDefaultModeModifiers}(?:#{regex_as_string})?/
        end
        return /(#{output_pattern.removeDefaultModeModifiers})/.updateGroupAttributes(self, other_regex, attributes)
    end
    def oneOrMoreOf(other_regex, attributes={})
        return /#{self.removeDefaultModeModifiers}((?:#{other_regex.removeDefaultModeModifiers})+)/.updateGroupAttributes(self, other_regex, attributes)
    end
    def zeroOrMoreOf(other_regex, attributes={})
        return /#{self.removeDefaultModeModifiers}((?:#{other_regex.removeDefaultModeModifiers})*)/.updateGroupAttributes(self, other_regex, attributes)
    end
end

# 
# Make safe failure for regex methods on strings
# 
class String 
    # make the removeDefaultModeModifiers do nothing for strings
    def removeDefaultModeModifiers()
        return self
    end
    # an alias operator for "removeDefaultModeModifiers"
    def -@()
        return self.removeDefaultModeModifiers
    end
end


# 
# Named patterns
# 
@space = /\s/
@spaces = /\s+/
@digit = /\d/
@digits = /\d+/
@standard_character = /\w/
@word = /\w+/
@word_boundary = /\b/
@white_space_start_boundary = /(?<=\s)(?=\S)/
@white_space_end_boundary = /(?<=\S)(?=\s)/

#
# Helpers
#
class NegatedSymbol
    def initialize(a_symbol)
        @symbol = a_symbol
    end
    def to_s
        return "not(#{@symbol.to_s})"
    end
    def to_sym
        return @symbol
    end
end

class Symbol
    def !@
        return NegatedSymbol.new(self)
    end
end

        def lookAheadFor(regex_pattern)
            return //.lookAheadFor(regex_pattern)
        end
        def lookAheadToAvoid(regex_pattern)
            return //.lookAheadToAvoid(regex_pattern)
        end
        def lookBehindFor(regex_pattern, attributes={})
            return //.lookBehindFor(regex_pattern, attributes)
        end
        def lookBehindToAvoid(regex_pattern, attributes={})
            return //.lookBehindToAvoid(regex_pattern, attributes)
        end
        def newPattern(regex_pattern, attributes={})
            return //.thenNewPattern(regex_pattern, attributes)
        end
        def maybe(regex_pattern, attributes={})
            return //.maybe(regex_pattern, attributes)
        end
        def oneOrMoreOf(other_regex, attributes={})
            return //.oneOrMoreOf(other_regex, attributes)
        end
        def zeroOrMoreOf(other_regex, attributes={})
            return //.zeroOrMoreOf(other_regex, attributes)
        end