//
//  validatestrings.swift
//  TestValidateStrings
//
//  Created by Peter Easdown on 7/11/2022.
//

import Foundation

/// Make sure that this script is not included in any targets, as this @main declaration will conflict with that of your actual target.
@main
class StringsParser {
    
    /// ParseState is used to manage the state of the parser.
    public indirect enum ParseState : Equatable {
        /// The parser is waiting for the opening quote of the key.
        case awaitingLeftStart
        /// Waiting for the closing quote of the key
        case awaitingLeftEnd
        /// Waiting for the '=' character between the key and value.
        case awaitingEquals
        /// Waiting for the opening quote of the value.
        case awaitingRightStart
        /// Waiting for the closing quote of the value.
        case awaitingRightEnd
        /// Waiting for the semicolon to finish off a key-value pair.
        case awaitingSemiColon
        
        /// The opening '/' of a comment has been detected, so this indicates that the state machine is waiting for either '/' or '*' to start the comment
        /// properly.
        case awaitingCommentStart(nextState: ParseState)
        /// Once inside a comment starting with '/*' this indicates that the machine is waiting for the '*' to close the comment.
        case awaitingCommentEnd(nextState: ParseState)
        /// This is only used for multiline comments and signifies waiting for the final '/' character.
        case awaitingCommentEnd2(nextState: ParseState)
        /// Used to force the parser to skip to the beginning of the next line.
        case awaitingNextLine(nextState: ParseState)
    }

    /// the patjh of the file being parsed.
    let path : String
    
    /// Set to true if any errors are generated.
    var errorFound = false
    
    /// A simple container for the lines in the file which makes it simpler to output a specific line as part of an error.
    var lines : Array<String.SubSequence> = Array()
    
    /// the state of the parsing machine.
    var state : ParseState = .awaitingLeftStart
    
    /// Outputs to standard output an Xcode "issue" in the syntax described at:
    ///       https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build
    /// - Parameters:
    ///   - path: the absolute path of the file being parsed
    ///   - type: the type of issue (should be one of "error", "warning" or "note" according to the above doc.
    ///   - msg: The message to append.
    ///   - line: The line number in the file being parsed to which the message relates.
    ///   - col: The column number of the character on the line.
    func outputMessage(_ path: String, _ type: String, _ msg: String, _ line: Int, _ col: Int) {
        // Print out the actual message using the correct formatting.
        print("\(path):\(line):\(col): \(type): \(msg)")
        
        // if the line number is valid, then output the line from the file and a marker to point to the character in the line.
        if (line != NSNotFound) && (line > 0) && (line <= lines.count) {
            print("\(lines[line-1])")
            
            if (col > 0) && (col <= lines[line-1].count) {
                let blanks = String(repeating: " ", count: col - 1).appending("^")
                print(blanks)
            }
        }
    }
    
    /// Output an error message with an optional link to another line.
    /// - Parameters:
    ///   - path: the absolute path of the file being parsed
    ///   - msg: The message to append.
    ///   - line: The line number in the file being parsed to which the message relates.
    ///   - col: The column number of the character on the line.
    ///   - forKeyAtLine: where the error relates to another line in the file, pass in a valid line number.  Pass in NSNotFound otherwise.
    ///   - andCol: where forKeyAtLine is a valid line number, this may be used to highlight the position in that line.
    func outputError(_ path: String, _ msg: String, _ line: Int, _ col: Int, _ forKeyAtLine: Int, _ andCol: Int) {
        // output the actual error message.
        outputMessage(path, "error", msg, line, col)
        
        // if we have a line number point back to the key, output a note for that.
        if forKeyAtLine != NSNotFound {
            outputMessage(path, "note", "related key is here", forKeyAtLine, andCol)
        }

        // ensure the tool exits with an error condition.
        errorFound = true
    }
    
    /// Executes the actual parser on the file provided at creation.
    /// - Returns: true if an error occurred whilst parsing the file, false if not.
    func parse() -> Bool {
        // handle any exceptions when trying to get the contents of the file.
        do {
            // get the file contents as a string.
            let content = try String(contentsOfFile: path)
            
            // initialise state of the parsing.
            
            // the running line number being parsed.
            var lineNumber = 1
            
            // the column number of the character being checked.
            var colNumber = 0
            
            // the line number of the last key to be successfully parsed.
            var lastLeftLine = NSNotFound
            
            // the position on the lastLeftLine of the key
            var lastLeftCol = NSNotFound
            
            // grab a copy of each individual line for possible error generation.
            lines = content.split(separator: "\n",omittingEmptySubsequences: false)

            // loop until all characters have been processed in the file.
            for ch in content {
                // normally, a given character is only processed once, however sometimes we need to reconsider the character
                // in case it is a valid part of the next token (typically the key).  So by default the count of times we consider a
                // character is 1, but we might increment that if needed.
                //
                var considerThisCharCount = 1
                
                // whilst the character is still being considered.
                //
                while considerThisCharCount > 0 {
                    colNumber += 1
                   
                    // have we started a new line?
                    if ch == "\n" {
                        lineNumber += 1
                        colNumber = 1
                        
                        // if something has caused us to skip to the next line, then use the reversion
                        // state as state to revert to.
                        //
                        switch state {
                        case .awaitingNextLine(let next):
                            state = next
                        default:
                            break
                        }
                    } else {
                        // Not a new line, so the character has to be treated with respect to the current machine state.
                        //
                        switch state {
                        case .awaitingLeftStart:
                            // do we have the beginning of the key?
                            if ch == "\"" {
                                state = .awaitingLeftEnd
                                lastLeftCol = colNumber
                                lastLeftLine = lineNumber
                                
                                // No, so is it a comment beginning?
                            } else if ch == "/" {
                                // yes, wait to see if the next character confirms this.
                                state = .awaitingCommentStart(nextState: .awaitingLeftStart)
                                
                                // no, but if it's anything other than whitespace then its an error
                            } else if !ch.isWhitespace {
                                outputError(path, "expected key", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                
                                state = .awaitingNextLine(nextState: .awaitingLeftStart)
                            }
                        case .awaitingLeftEnd:
                            // do we have the closing quote for the key?
                            if ch == "\"" {
                                state = .awaitingEquals
                            }
                        case .awaitingEquals:
                            // do we have the equals symbol.
                            if ch == "=" {
                                // yes start looking for the value.
                                state = .awaitingRightStart
                                
                                // No, so is it a comment beginning?
                            } else if ch == "/" {
                                // yes, wait to see if the next character confirms this.
                                state = .awaitingCommentStart(nextState: .awaitingEquals)
                                
                                // no, but if it's anything other than whitespace then its an error
                            } else if !ch.isWhitespace {
                                outputError(path, "expected equals sign '='", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                
                                state = .awaitingNextLine(nextState: .awaitingLeftStart)
                            }
                        case .awaitingRightStart:
                            // has the values opening quote been found?
                            if ch == "\"" {
                                // yes, start looking for the closing quote
                                state = .awaitingRightEnd
                                
                                // No, so is it a comment beginning?
                            } else if ch == "/" {
                                // yes, wait to see if the next character confirms this.
                                state = .awaitingCommentStart(nextState: state)
                                
                                // no, but if it's anything other than whitespace then its an error
                            } else if !ch.isWhitespace {
                                outputError(path, "expected value string", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                
                                state = .awaitingNextLine(nextState: .awaitingLeftStart)
                            }
                        case .awaitingRightEnd:
                            // if we have the closing quote for the value, then start looking for the
                            // semicolon.
                            if ch == "\"" {
                                state = .awaitingSemiColon
                            }
                        case .awaitingSemiColon:
                            // have we found the semicolon?
                            if ch == ";" {
                                state = .awaitingLeftStart
                                
                                // No, so is it a comment beginning?
                            } else if ch == "/" {
                                // yes, wait to see if the next character confirms this.
                                state = .awaitingCommentStart(nextState: state)
                                
                                // no, but if it's anything other than whitespace then its an error
                            } else if !ch.isWhitespace {
                                outputError(path, "expected semicolon ';'", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                state = .awaitingLeftStart
                                
                                // we want to take another look at this character as the possible start of the next
                                // key, so increment the consideration count.
                                //
                                considerThisCharCount += 1
                            }
                        case .awaitingCommentStart(let next):
                            // so we've previously found a / character.  is this next one another / or a *?
                            if ch == "/" {
                                // comment started for single line. traverse to the next line.
                                state = .awaitingNextLine(nextState: next)
                                
                                // a multiline comment has started.
                            } else if ch == "*" {
                                state = .awaitingCommentEnd(nextState: next)
                            }
                        case .awaitingCommentEnd(let next):
                            // are we looking at the beginning of the end of a multiline comment?
                            if ch == "*" {
                                // yes, so now look for the / to end it properly.
                                state = .awaitingCommentEnd2(nextState: next)
                            }
                        case .awaitingCommentEnd2(let next):
                            // if we have truly ended a multiline comment, then great, otherwise, we're back to looking
                            // for the *.
                            if ch == "/" {
                                state = next
                            } else {
                                state = .awaitingCommentEnd(nextState: next)
                            }
                        case .awaitingNextLine:
                            // when waiting for the next line, just ignore all characters.
                            break
                        }
                    }
                    
                    considerThisCharCount -= 1
                }
            }
            
            // If the parsing finishes, and the state isn't awaitingLeftStart, then there was an error where a key/value wasn't
            // completed.
            //
            if state != .awaitingLeftStart {
                switch state {
                case .awaitingLeftStart:
                    // not an error.
                    break
                case .awaitingLeftEnd:
                    outputError(path, "end of file reached when expecting end of key", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingEquals:
                    outputError(path, "end of file reached when expecting =", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingRightStart:
                    outputError(path, "end of file reached when expecting value string", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingRightEnd:
                    outputError(path, "end of file reached when expecting end of value", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingSemiColon:
                    outputError(path, "end of file reached when expecting semicolon", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingCommentStart:
                    outputError(path, "end of file reached when expecting comment start", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingCommentEnd:
                    outputError(path, "end of file reached when expecting end of comment", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingCommentEnd2:
                    outputError(path, "end of file reached when expecting end of comment", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                case .awaitingNextLine:
                    // not an error.
                    break
                }
            }
            
            return errorFound
        } catch {
            print("Unable to parse strings file: \(path)")
            return true
        }
    }
    
    init(fileName: String) {
        self.path = fileName
    }
    
    static func main() {
        // We need at least one argument (the filename).   the zeroth argument is the name of the command, and
        // the 1st is our actual argument.
        //
        if ProcessInfo.processInfo.arguments.count > 1 {
            let path = ProcessInfo.processInfo.arguments[1]
            
            // create a parser
            let parser : StringsParser = StringsParser(fileName: path)
            
            // and parse the file.
            if parser.parse() {
                exit(1)
            } else {
                exit(0)
            }
        } else {
            print("validatestrings script requires a single argument specifying the path of a *.strings file.")
            exit(1)
        }
    }
}
