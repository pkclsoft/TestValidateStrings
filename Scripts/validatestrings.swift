//
//  validatestrings.swift
//  TestValidateStrings
//
//  Created by Peter Easdown on 7/11/2022.
//

import Foundation

@main
class MyScript {
    public enum ParseState : Int {
        case awaitingLeftStart = 0
        case awaitingLeftEnd = 1
        case awaitingEquals = 2
        case awaitingRightStart = 3
        case awaitingRightEnd = 4
        case awaitingSemiColon = 5
        
        case awaitingCommentStart = 6
        case awaitingCommentEnd = 7
        case awaitingCommentEnd2 = 8
        
        case awaitingNextLine = 9
    }
    
    static var errorFound = false
    static var lines : Array<String.SubSequence> = Array()

    static func outputMessage(_ path: String, _ type: String, _ msg: String, _ line: Int, _ col: Int) {
        print("\(path):\(line):\(col): \(type): \(msg)")
        
        print("\(lines[line-1])")
        let blanks = String(repeating: " ", count: col - 1).appending("^")
        print(blanks)
    }
    
    static func outputError(_ path: String, _ msg: String, _ line: Int, _ col: Int, _ forKeyAtLine: Int, _ andCol: Int) {
        outputMessage(path, "error", msg, line, col)
        
        if forKeyAtLine != NSNotFound {
            outputMessage(path, "note", "previous definition is here", forKeyAtLine, andCol)
        }

        errorFound = true
    }
    
    static func main() {
        if ProcessInfo.processInfo.arguments.count > 1 {
            let path = ProcessInfo.processInfo.arguments[1]

            var state : ParseState = .awaitingLeftStart
            var reversionState : ParseState = .awaitingLeftStart
            
            do {
                let content = try String(contentsOfFile: path)
                var lineNumber = 1
                var colNumber = 0
                var lastLeftLine = NSNotFound
                var lastLeftCol = NSNotFound
                
                lines = content.split(separator: "\n",omittingEmptySubsequences: false)

                for ch in content {
                    var considerThisCharCount = 1
                    
                    while considerThisCharCount > 0 {
                        colNumber += 1
                        
                        if ch == "\n" {
                            lineNumber += 1
                            colNumber = 1
                            
                            if state == .awaitingNextLine {
                                state = reversionState
                            }
                        } else {
                            switch state {
                            case .awaitingLeftStart:
                                if ch == "\"" {
                                    state = .awaitingLeftEnd
                                    lastLeftCol = colNumber
                                    lastLeftLine = lineNumber
                                } else if ch == "/" {
                                    reversionState = state
                                    state = .awaitingCommentStart
                                } else if ch != " " {
                                    outputError(path, "expected key", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                    reversionState = .awaitingLeftStart
                                    state = .awaitingNextLine
                                }
                            case .awaitingLeftEnd:
                                if ch == "\"" {
                                    state = .awaitingEquals
                                }
                            case .awaitingEquals:
                                if ch == "=" {
                                    state = .awaitingRightStart
                                } else if ch == "/" {
                                    reversionState = state
                                    state = .awaitingCommentStart
                                } else if ch != " " {
                                    outputError(path, "expected equals sign '='", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                    reversionState = .awaitingLeftStart
                                    state = .awaitingNextLine
                                }
                            case .awaitingRightStart:
                                if ch == "\"" {
                                    state = .awaitingRightEnd
                                } else if ch == "/" {
                                    reversionState = state
                                    state = .awaitingCommentStart
                                } else if ch != " " {
                                    outputError(path, "expected value string", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                    state = .awaitingNextLine
                                }
                            case .awaitingRightEnd:
                                if ch == "\"" {
                                    state = .awaitingSemiColon
                                }
                            case .awaitingSemiColon:
                                if ch == ";" {
                                    state = .awaitingLeftStart
                                } else if ch == "/" {
                                    reversionState = state
                                    state = .awaitingCommentStart
                                } else if ch != " " {
                                    outputError(path, "expected semicolon ';'", lineNumber, colNumber, lastLeftLine, lastLeftCol)
                                    state = .awaitingLeftStart
                                    
                                    // we want to take another look at this character as the possible start of the next
                                    // key, so increment the count.
                                    //
                                    considerThisCharCount += 1
                                }
                            case .awaitingCommentStart:
                                if ch == "/" {
                                    // comment started for single line. traverse to the next line.
                                    state = .awaitingNextLine
                                } else if ch == "*" {
                                    state = .awaitingCommentEnd
                                }
                            case .awaitingCommentEnd:
                                if ch == "*" {
                                    state = .awaitingCommentEnd2
                                }
                            case .awaitingCommentEnd2:
                                if ch == "/" {
                                    state = reversionState
                                }
                            case .awaitingNextLine:
                                break
                            }
                        }
                        
                        considerThisCharCount -= 1
                    }
                }
                
                // If the parsing finishes, and the state isn't awaitingLeftStart, then there was an error.
                //
                if state != .awaitingLeftStart {
                    switch state {
                        
                    case .awaitingLeftStart:
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
                        break
                    }
                }
            } catch {
                print("Unable to parse strings file: \(path)")
                exit(1)
            }
            
            if errorFound {
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
