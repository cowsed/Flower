module Compiler exposing (..)

import Analysis.Analyzer exposing (GoodProgram)
import Analysis.Explanations
import Html
import Parser.AST as AST
import Parser.Lexer as Lexer exposing (Token, token_to_str)
import Parser.Parser as Parser
import Parser.ParserCommon as ParserCommon
import Parser.ParserExplanations as ParserExplanations
import Analysis.Util exposing (AnalysisError)

type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error (List Token)
    | Analysis AnalysisError


explain_toks : List Token -> Html.Html msg
explain_toks toks =
    toks |> List.map token_to_str |> String.join "\n" |> (\s -> Html.textarea [] [ Html.text s ])


explain_error : CompilerError -> Html.Html msg
explain_error e =
    case e of
        Lex le ->
            Html.div []
                [ Html.h1 [] [ Html.text "Lexer error" ]
                , Lexer.explain_error le
                ]

        Parse pe toks ->
            Html.div []
                [ Html.h1 [] [ Html.text "Parser error" ]
                , ParserExplanations.explain_error pe
                , explain_toks toks
                ]

        Analysis ae ->
            Html.div []
                [ Html.h1 [] [ Html.text "Analysis error" ]
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
        |> Result.andThen (\prog -> Analysis.Analyzer.analyze prog |> Result.map (\gp -> gp ) |> Result.mapError (\e -> Analysis e))
