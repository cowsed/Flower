module Compiler exposing (..)

import Analysis.Analyzer exposing (GoodProgram)
import Analysis.Explanations
import Analysis.Util exposing (AnalysisError)
import Element
import Element.Font as Font
import Element.Border as Border

import Parser.Lexer as Lexer exposing (Token, token_to_str)
import Parser.Parser as Parser
import Parser.ParserCommon as ParserCommon
import Parser.ParserExplanations as ParserExplanations
import Element.Background as Background
import Pallete
import Parser.AST


type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error (List Token)
    | Analysis AnalysisError Parser.AST.Program


explain_toks : List Token -> Element.Element msg
explain_toks toks =
    toks |> List.map token_to_str |> String.join "\n" |> (\s -> Element.el [Font.family [Font.monospace], Background.color Pallete.bg1_c] (Element.text s))


explain_error : CompilerError -> Element.Element msg
explain_error e =
    case e of
        Lex le ->
            Element.column [Border.solid, Border.rounded 8, Border.color Pallete.fg_c]
                [ Element.el [ Font.size 30 ] (Element.text "Lexer error")
                , Lexer.explain_error le
                ]

        Parse pe toks ->
            Element.column [Border.solid, Border.rounded 8, Border.color Pallete.fg_c]
                [ Element.el [ Font.size 30 ] (Element.text "Parser error")
                , ParserExplanations.explain_error pe
                , explain_toks toks
                ]

        Analysis ae _ ->
            Element.column [Border.solid, Border.rounded 8, Border.color Pallete.fg_c]
                [ Element.el [ Font.size 30 ] (Element.text "Analysis error")
                , Analysis.Explanations.explain_error ae
                ]


compile : String -> Result CompilerError GoodProgram
compile src =
    let
        lex_result : Result CompilerError (List Token)
        lex_result =
            Lexer.lex src |> Result.mapError (\e -> Lex e)
    in
    lex_result
        |> Result.andThen (\toks -> Parser.parse toks |> Result.mapError (\e -> Parse e toks))
        |> Result.andThen (\prog -> Analysis.Analyzer.analyze prog |> Result.mapError (\e -> Analysis e prog))
