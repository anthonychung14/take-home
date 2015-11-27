module Router where

import Http.Response.Write exposing (writeHtml
  , writeJson
  , writeElm, writeFile
  , writeNode, writeRedirect)

import Http.Request exposing (emptyReq
  , Request, Method(..)
  , parseQuery, getQueryField
  , getFormField, getFormFiles
  , setForm
  )

import Http.Response exposing (Response)

import Model exposing (Connection, Model)
import Client.App exposing (index, genericErrorView)
import Client.Signup.Views exposing (signUpForTakeHomeView)
import Generators exposing (generateSuccessPage
  , generateSignupPage, generateWelcomePage
  , generateTestPage, generateAdminPage
  )

import Client.Admin.Views exposing (loginView)

import Shared.Routes exposing (routes)

import Task exposing (..)
import Signal exposing (..)
import Json.Encode as Json
import Maybe
import Result exposing (Result)
import Effects exposing (Effects)
import Dict
import Regex
import String

import Env
import Converters

import Debug

type Action
  = Incoming Connection
  | Run ()
  | Noop

type StartAppAction
  = Init Model
  | Update Action

{-| when we don't want to 500, write an error view
-}
handleError : Response -> Task a () -> Task b ()
handleError res errTask =
  errTask
    |> (flip Task.onError) (\err -> writeNode (genericErrorView err) res)

runRoute task =
  task
    |> Task.map Run
    |> Effects.task

hasQuery url =
  String.contains "?" url

queryPart url =
  String.indexes "?" url
    |> (\xs ->
      case xs of
        [] -> ""
        x::_ -> String.dropLeft (x + 1) url
      )

{-| route each request/response pair and write a response
-}
routeIncoming : Connection -> Model -> (Model, Effects Action)
routeIncoming (req, res) model =
  let
    runRouteWithErrorHandler =
      (handleError res) >> runRoute
    url =
      req.url

    generatePOST generator =
      (setForm req
        |> (flip andThen) (\req -> generator res req model)
        |> runRouteWithErrorHandler)
  in
    case req.method of
      GET ->
        if url == routes.index then
          model =>
            (writeNode (signUpForTakeHomeView model.testConfig) res
              |> runRouteWithErrorHandler)
        else if url == routes.login then
          model =>
            (writeNode loginView res
              |> runRouteWithErrorHandler)
        else
          case hasQuery url of
            False ->
              model =>
                (writeFile url res
                    |> runRouteWithErrorHandler)
            True ->
              case parseQuery <| queryPart url of
                Err _ ->
                  model =>
                    (Task.fail "failed to parse"
                      |> runRouteWithErrorHandler)
                Ok bag ->
                  case getQueryField "token" bag of
                    Nothing ->
                      model =>
                        (Task.fail ("Failed to find anything " ++ url)
                          |> runRouteWithErrorHandler)

                    Just token ->
                      model =>
                        (generateWelcomePage token res model
                          |> runRouteWithErrorHandler)

      POST ->
        if url == routes.apply then
          model =>
            generatePOST generateSuccessPage
        else if url == routes.signup then
          model =>
            generatePOST generateSignupPage
        else if url == routes.startTest then
          model =>
            generatePOST generateTestPage
        else if url == routes.login then
          model =>
            generatePOST generateAdminPage
        else
          model =>
            (handleError res (Task.fail "Route not found")
              |> runRouteWithErrorHandler)

      NOOP ->
        model => Effects.none

      _ ->
        model =>
          (writeJson (Json.string "unknown method!") res
            |> runRoute)


update : Action -> Model -> (Model, Effects Action)
update action model =
  case action of
    Incoming connection -> routeIncoming connection model
    Run _ -> (model, Effects.none)
    Noop -> (model, Effects.none)

uniqueUrl : String -> Maybe String
uniqueUrl url =
  let
    uniqueRegex =
      Regex.regex "?token=(.+)(&.)"
  in
    case Regex.find (Regex.AtMost 1) uniqueRegex url of
      [] -> Nothing
      uniqueMatch::_ ->
        case uniqueMatch.submatches of
          uniqueString::_::[] -> uniqueString
          _ -> Nothing

(=>) = (,)
