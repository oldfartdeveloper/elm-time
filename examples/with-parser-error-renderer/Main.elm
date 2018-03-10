module Main exposing (main)

{-| Ilias' work on a parser renderer; he gave this to
me to provide a renderer for the `elm-tools/parser` package.

After looking briefly at it, I'm worried that it is specifying
the strings too much; those strings are generated by the
`Parser` package itself.

Hence, am toying w/ idea of scaling this back to work only
with the `Parser`


# Main entry

@docs main

-}

import Char
import Html exposing (Html, text, pre)
import Parser exposing ((|.), (|=), Parser)
import Set exposing (Set)
import Time.Date
import Time.DateTime exposing (fromISO8601)


{-| The "entry"
-}
main : Html msg
main =
    case mainProg "2100-12-29T01:00:01-0100" of
        Ok v ->
            text <| toString v

        Err e ->
            let
                msg =
                    errorToString primitives e
                    ++ "\n\n"
                    ++ toString e
            in
                Html.pre [] [ text <| msg ]


primitives : Set String
primitives =
    Set.fromList [ "date" ]


mainProg : String -> Result Parser.Error Time.DateTime.DateTime
mainProg input =
    Time.DateTime.fromISO8601 input


digits : Int -> Parser Int
digits count =
    Parser.inContext "digits" <|
        (Parser.keep (Parser.Exactly count) Char.isDigit
            |> Parser.andThen (fromResult << String.toInt)
        )


fromResult : Result String Int -> Parser Int
fromResult result =
    case result of
        Ok i ->
            Parser.succeed i

        Err msg ->
            Parser.fail msg



-- stringifier


errorToString : Set String -> Parser.Error -> String
errorToString primitives error =
    let
        findContext : List Parser.Context -> String
        findContext contexts =
            List.foldl
                (\ctx acc ->
                    if acc == Nothing then
                        if Set.member ctx.description primitives then
                            Nothing
                        else
                            Just <| forContext ctx
                    else
                        acc
                )
                Nothing
                contexts
                |> Maybe.withDefault noContext

        ( cause, context ) =
            case error.context of
                [] ->
                    ( Nothing, noContext )

                x :: xs ->
                    if Set.member x.description primitives then
                        ( Just x.description, findContext xs )
                    else
                        ( Nothing, forContext x )
    in
    context
        ++ "\n\n    "
        ++ relevantSource error
        ++ "\n    "
        ++ marker error.col
        ++ "\n\n"
        ++ (reflow <| describeProblem cause error.problem)


reflow : String -> String
reflow s =
    let
        flowLine : String -> String
        flowLine s =
            String.words s
                |> makeSentences
                |> String.join "\n"

        makeSentences : List String -> List String
        makeSentences words =
            List.foldl
                (\word ( sentence, acc ) ->
                    let
                        combined =
                            case sentence of
                                Nothing ->
                                    word

                                Just s ->
                                    s ++ " " ++ word
                    in
                    if String.length combined > 72 then
                        ( Just word, sentence :: acc )
                    else
                        ( Just combined, acc )
                )
                ( Nothing, [] )
                words
                |> uncurry (::)
                |> reverseFilterMap identity
    in
    s
        |> String.lines
        |> List.map flowLine
        |> String.join "\n"


reverseFilterMap : (a -> Maybe b) -> List a -> List b
reverseFilterMap toMaybe list =
    List.foldl
        (\x acc ->
            case toMaybe x of
                Just y ->
                    y :: acc

                Nothing ->
                    acc
        )
        []
        list


relevantSource : Parser.Error -> String
relevantSource { row, source } =
    String.lines source
        |> List.drop (row - 1)
        |> List.head
        |> Maybe.withDefault ""


describeProblem : Maybe String -> Parser.Problem -> String
describeProblem probableCause problem =
    case problem of
        Parser.BadInt ->
            "I'm trying to read an integer here."

        Parser.BadFloat ->
            "I'm trying to read a float here"

        Parser.BadRepeat ->
            case probableCause of
                Just cause ->
                    "I got stuck here. I'm looking for " ++ cause ++ "."

                Nothing ->
                    "I got stuck here. I'm probably looking for something specific and not making any progress here."

        Parser.ExpectingEnd ->
            "I expected this string to stop here, but it goes on."

        Parser.ExpectingSymbol s ->
            "I expected a `" ++ s ++ "` here."

        Parser.ExpectingKeyword s ->
            "I'm looking for a keyword `" ++ s ++ "`"

        Parser.ExpectingVariable ->
            "I'm expecting a variable here."

        Parser.ExpectingClosing s ->
            "I'm looking for a closing `" ++ s ++ "` here."

        Parser.Fail s ->
            "I " ++ s

        Parser.BadOneOf problems ->
            "I tried a few things here:\n\n"
                ++ (List.map (describeProblem probableCause) problems |> String.join "\n\n")


marker : Int -> String
marker col =
    String.repeat (col - 1) " " ++ "^"


forContext : Parser.Context -> String
forContext { description } =
    "Failed to parse the '" ++ description ++ "' segment:"


noContext : String
noContext =
    "I ran into a problem parsing this:"
