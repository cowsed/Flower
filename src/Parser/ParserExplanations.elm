module Parser.ParserExplanations exposing (..)

import Element
import Element.Font as Font
import Language.Language as Language exposing (Identifier(..))
import Language.Syntax
import Pallete as Pallete
import Parser.AST as AST exposing (AliasDefinition, Expression(..), FullName, TypeDefinitionType(..), stringify_fullname)
import Parser.Lexer as Lexer
import Parser.ParserCommon as ParserCommon
import Ui exposing (color_text)
import Util
import Element.Border as Border
import Language.Syntax as Syntax



-- Syntaxifications ==========================================


syntaxify_namedarg : AST.QualifiedTypeWithName -> List (Element.Element msg)
syntaxify_namedarg na =
    [ symbol_highlight (Language.stringify_identifier na.name)
    , Element.text ": "
    , syntaxify_fullname na.typename.thing
    ]


syntaxify_keyword : String -> Element.Element msg
syntaxify_keyword s =
    Element.row [ Font.color Pallete.red_c ] [ Element.text s ]


symbol_highlight : String -> Element.Element msg
symbol_highlight s =
    Element.el [ Font.color Pallete.orange_c ] (Element.text s)


syntaxify_string_literal : String -> Element.Element msg
syntaxify_string_literal s =
    Element.el [ Font.color Pallete.blue_c ] (Element.text ("\"" ++ s ++ "\""))


syntaxify_number_literal : String -> Element.Element msg
syntaxify_number_literal s =
    color_text Pallete.aqua_c s


syntaxify_identifier : Identifier -> Element.Element msg
syntaxify_identifier id =
    case id of
        SingleIdentifier s ->
            symbol_highlight s

        QualifiedIdentifiers ls ->
            ls |> List.map symbol_highlight |> List.intersperse (Element.text ".") |> Element.row []


syntaxify_literal : Language.Syntax.LiteralType -> String -> Element.Element msg
syntaxify_literal l s =
    case l of
        Language.Syntax.StringLiteral ->
            syntaxify_string_literal ("\"" ++ s ++ "\"")

        Language.Syntax.NumberLiteral ->
            syntaxify_number_literal s


syntaxify_fullname : FullName -> Element.Element msg
syntaxify_fullname fn =
    case fn of
        AST.Literal l s ->
            syntaxify_literal l s |> (\t -> Element.row [] [ t ])

        AST.NameWithoutArgs id ->
            syntaxify_identifier id

        AST.NameWithArgs nl ->
            Element.row []
                [ syntaxify_identifier nl.base
                , Element.text "["
                , Element.row [] (nl.args |> List.map (\f -> syntaxify_fullname f.thing) |> List.intersperse (Element.text ", "))
                , Element.text "]"
                ]

        AST.ReferenceToFullName fn2 ->
            Element.row [] [ Element.text "&", syntaxify_fullname fn2.thing ]

        AST.Constrained name constraint ->
            Element.row [] [ syntaxify_fullname name.thing, Element.text " | ", syntaxify_expression constraint.thing ]


syntaxify_expression : AST.Expression -> Element.Element msg
syntaxify_expression expr =
    case expr of
        AST.NameLookup n ->
            syntaxify_fullname n.thing

        AST.FunctionCallExpr fcall ->
            Element.row []
                [ syntaxify_fullname fcall.thing.fname.thing
                , Element.text "("
                , Element.row [] (fcall.thing.args |> List.map (\arg -> syntaxify_expression arg.thing) |> List.intersperse (Element.text ", "))
                , Element.text ")"
                ]

        AST.Parenthesized e ->
            Element.row [] [ Element.text "(", syntaxify_expression e.thing, Element.text ")" ]

        AST.LiteralExpr lt s ->
            case lt of
                Language.Syntax.StringLiteral ->
                    syntaxify_string_literal s

                Language.Syntax.NumberLiteral ->
                    syntaxify_number_literal s


syntaxify_fheader : AST.FunctionHeader -> Element.Element msg
syntaxify_fheader header =
    let
        pretty_arg_lst : List (Element.Element msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ Element.text ", " ] (List.map syntaxify_namedarg header.args))

        lis =
            List.concat [ [ Element.text "(" ], pretty_arg_lst, [ Element.text ")" ] ]

        ret : Element.Element msg
        ret =
            Element.row []
                (case header.return_type of
                    Just typ ->
                        [ Element.row [] [ Element.text " 🡒 ", Element.row [] [ syntaxify_fullname typ.thing ] ] ]

                    Nothing ->
                        [ Element.text " " ]
                )
    in
    Element.row [] (List.append lis [ ret ])



-- Explanations ==============================================


explain_error : ParserCommon.Error -> Element.Element msg
explain_error e =
    case e of
        ParserCommon.Unimplemented p reason ->
            Element.column [ Font.color Pallete.red_c ]
                [ Element.text "!!!Unimplemented!!!"
                , Element.text (reason ++ "\n")
                , Element.text "Program so far"
                , explain_program p
                ]

        _ ->
            Element.el [ Font.color Pallete.red_c, Font.family [ Font.monospace ] ] <|
                Element.text (stringify_error e)


explain_struct : AST.StructDefnition -> Element.Element msg
explain_struct str =
    Element.row []
        [ Element.text "Structure with name "
        , Element.text (AST.stringify_fullname str.name.thing)
        , Element.column []
            (str.fields
                |> List.map
                    (\f ->
                        Element.row []
                            [ Element.text "field "
                            , Element.text (Language.stringify_identifier f.name.thing)
                            , Element.text " of type "
                            , Element.text (AST.stringify_fullname f.typename.thing)
                            ]
                    )
            )
        ]


explain_enum_field : AST.EnumField -> Element.Element msg
explain_enum_field field =
    if List.length field.args > 0 then
        Element.row []
            [ Element.text field.name
            , Element.text " with args "
            , Element.column []
                (field.args |> List.map (\f -> stringify_fullname f.thing) |> List.map Element.text)
            ]

    else
        Element.text field.name


explain_enum : AST.EnumDefinition -> Element.Element msg
explain_enum enum =
    Element.row []
        [ Element.text ("Enum with name " ++ stringify_fullname enum.name.thing ++ " and fields")
        , Element.column
            []
            (enum.fields |> List.map explain_enum_field)
        ]


explain_program : AST.Program -> Element.Element msg
explain_program prog =
    let
        imports =
            Util.collapsable_el (Element.text "Imports") (Element.column [] (List.map (\s -> Element.text s.thing) prog.imports))

        funcs =
            Util.collapsable_el (Element.text "Global Functions")
                (Element.column []
                    (List.map
                        (\f ->
                            Util.collapsable_el
                                (Element.row []
                                    [ Element.text (stringify_fullname f.name.thing)
                                    , syntaxify_fheader f.header
                                    ]
                                )
                                (explain_statments f.statements)
                        )
                        prog.global_functions
                    )
                )

        typedefs =
            Util.collapsable_el (Element.text "Global typedefs")
                (Element.column []
                    (List.map
                        (\f ->
                            explain_typedef f
                        )
                        prog.global_typedefs
                    )
                )
    in
    Element.column [ Font.size 14 ]
        [ Element.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name)
        , imports
        , funcs
        , typedefs
        ]


explain_typedef : TypeDefinitionType -> Element.Element msg
explain_typedef tt =
    case tt of
        StructDefType s ->
            Util.collapsable_el
                (Element.text (AST.stringify_fullname s.name.thing))
                (explain_struct s)

        EnumDefType s ->
            Util.collapsable_el
                (Element.text (AST.stringify_fullname s.name.thing))
                (explain_enum s)

        AliasDefType s ->
            explain_alias s


explain_alias : AliasDefinition -> Element.Element msg
explain_alias ad =
    Element.column []
        [ Element.text "Type alias of "
        , Element.text (AST.stringify_fullname ad.name.thing)
        , Element.text " to "
        , Element.text (AST.stringify_fullname ad.alias_to.thing)
        ]


tab : Element.Element msg
tab =
    Element.text "    "


tabs : Int -> Element.Element msg
tabs number =
    Element.text (String.repeat number "    ")


stringify_error : ParserCommon.Error -> String
stringify_error e =
    case e of
        ParserCommon.NoModuleNameGiven ->
            "No Module Name Given. The First non comment line in a program must be `module module_name`"

        ParserCommon.NonStringImport location ->
            "I expected a string literal as an import but got this nonsense instead\n" ++ Syntax.show_source_view location

        ParserCommon.Unimplemented _ reason ->
            "Unimplemented: " ++ reason

        ParserCommon.NeededMoreTokens why ->
            "Couldnt end because I needed more tokens: " ++ why

        ParserCommon.UnknownOuterLevelObject loc ->
            "The only things allowed at this point are `import`, a variable or a function definition, or a type definition (struct, alias, enum)\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedNameAfterFn loc ->
            "Expected a name after the fn keyword to name a function. Something like `fn name()` \n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedOpenParenAfterFn s loc ->
            "Expected a close paren after the fn name `fn " ++ s ++ "()` \n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedToken explanation loc ->
            explanation ++ "\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedTypeName loc ->
            "Expected a type name here.\nDid you maybe use a keyword like `return`, `fn`, `var`? You can't do that\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedEndOfArgListOrComma loc ->
            "Expected a comma to continue arg list or a close paren to end it\n" ++ Syntax.show_source_view loc

        ParserCommon.FailedTypeParse tpe ->
            case tpe of
                ParserCommon.Idk loc ->
                    "Failed to parse type\n" ++ Syntax.show_source_view loc

                ParserCommon.UnexpectedTokenInTypesGenArgList loc ->
                    "Unexpexted otken in types generic arg list \n" ++ Syntax.show_source_view loc

        ParserCommon.FailedNamedTypeParse tpe ->
            case tpe of
                ParserCommon.TypeError tp ->
                    stringify_error (ParserCommon.FailedTypeParse tp)

                ParserCommon.NameError loc ne ->
                    "Failed to parse name of name: Type. " ++ ne ++ "\n" ++ Syntax.show_source_view loc

        ParserCommon.KeywordNotAllowedHere loc ->
            "This Keyword is not allowed here\n" ++ Syntax.show_source_view loc

        ParserCommon.FailedExprParse er ->
            case er of
                ParserCommon.IdkExpr loc s ->
                    "Failed to parse expr: " ++ s ++ "\n" ++ Syntax.show_source_view loc

                ParserCommon.ParenWhereIDidntWantIt loc ->
                    "I was expecting an expression but I found this parenthesis instead\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedFunctionBody loc got ->
            "Expected a `{` to start the function body but got `" ++ Lexer.syntaxify_token got ++ "`\n" ++ Syntax.show_source_view loc

        ParserCommon.RequireInitilizationWithValue loc ->
            "When you are initilizaing something `var a: Type = xyz you need that = xyz or else that thing is unitialized\n" ++ Syntax.show_source_view loc

        ParserCommon.UnknownThingWhileParsingFuncCallOrAssignment loc ->
            "I was parsing the statements of a function (specifically an assignment or function call) and found something random\n" ++ Syntax.show_source_view loc

        ParserCommon.FailedFuncCallParse er ->
            case er of
                ParserCommon.IdkFuncCall loc s ->
                    "Failed to parse a function call: " ++ s ++ "\n" ++ Syntax.show_source_view loc

                ParserCommon.ExpectedAnotherArgument loc ->
                    "I expected another argument after this comma\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedOpenCurlyForFunction loc ->
            "I expected an opening curly to start a function body\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedNameAfterDot loc ->
            "I expected another name after this dot. ie `a.b.c` but got " ++ Syntax.show_source_view_not_line loc ++ "\n" ++ Syntax.show_source_view loc

        ParserCommon.FailedBlockParse er ->
            case er of
                ParserCommon.None ->
                    "Statement Parse Error"

        ParserCommon.UnexpectedTokenInGenArgList loc ->
            "Unexpected Token in generic arg list\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedNameForStruct loc ->
            "I expected a name for a structure here but all i got was\n" ++ Syntax.show_source_view loc

        ParserCommon.UnknownTokenInEnumBody loc ->
            "Unexpected token in enum body\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedCloseParenInEnumField loc ->
            "I got to the end of the line without a ). Enum fields should look like `Field(Type1, Type2)`\n" ++ Syntax.show_source_view loc

        ParserCommon.ExpectedEqualInTypeDeclaration loc ->
            "I expected an = like `type Name =` \n" ++ Syntax.show_source_view loc


explain_expression : AST.Expression -> Element.Element msg
explain_expression expr =
     case expr of
        AST.NameLookup nwargs ->
            Element.row [] [ Element.text "name look up of ",Ui.code_text <| stringify_fullname nwargs.thing  ]

        AST.FunctionCallExpr fcall ->
            Element.column [Border.width 1]
                [ Element.row [] [ Element.text "func call: ", Element.text (AST.stringify_fullname fcall.thing.fname.thing) |> Ui.code, Element.text " with args " ]
                , Element.row [] [Element.text "  ", Element.column [] (fcall.thing.args |> List.map (\a -> explain_expression a.thing))]
                ]

        AST.LiteralExpr lt s ->
            case lt of
                Language.Syntax.StringLiteral ->
                    Element.row [] [ Element.text ("String Literal: " ++ s) ]

                Language.Syntax.NumberLiteral ->
                    Element.row [] [ Element.text ("Number Literal: " ++ s) ]

        AST.Parenthesized e ->
            Element.row [Border.width 1] [ Element.text "(", explain_expression e.thing, Element.text ")" ]


explain_statement : AST.Statement -> Element.Element msg
explain_statement s =
    case s of
        AST.ReturnStatement expr ->
            Element.row []
                [ Element.text "return: "
                , case expr of
                    Just e ->
                        explain_expression e.thing

                    Nothing ->
                        Element.text "Nothing"
                ]

        AST.CommentStatement src ->
            Element.row [] [ Element.text "// ", Element.text src ]

        AST.InitilizationStatement name expr ->
            Element.row [] [ Element.text ("Initialize `" ++ Language.stringify_identifier name.name ++ "` of type " ++ AST.stringify_fullname name.typename.thing ++ " to "), explain_expression expr.thing ]

        AST.AssignmentStatement name expr ->
            Element.row [] [ Element.text "assigning ", Ui.code_text <| Language.stringify_identifier name, Element.text " with ", explain_expression expr.thing ]

        AST.FunctionCallStatement fcal ->
            Element.row []
                [ Element.text ("call the function " ++ AST.stringify_fullname fcal.thing.fname.thing ++ " with args:")
                , Element.column []
                    (fcal.thing.args
                        |> List.map (\n -> explain_expression n.thing)
                    )
                ]

        AST.IfStatement expr block ->
            Element.row [] [ Element.text "If statement, checks (", explain_expression expr.thing, Element.text ") then does", explain_statments block ]

        AST.WhileStatement expr block ->
            Element.row [] [ Element.text "While statement, checks (", explain_expression expr.thing, Element.text ") then does", explain_statments block ]


explain_statments : List AST.Statement -> Element.Element msg
explain_statments statements =
    Element.column [] (List.map (\s -> explain_statement s) statements)
