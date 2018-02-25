{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module Main where

import Control.Applicative ((<$>))
import Control.Monad.Trans.Class (lift)
import Data.Map (fromList)
import Data.Monoid ((<>))
import Database.HDBC
import Database.HDBC.Sqlite3
import Data.Aeson (toJSON)
-- import Control.Applicative ((<$>))
import Controllers.Home (home, docs, login)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Network.Wai.Middleware.Static        (addBase, noDots,
                                             staticPolicy, (>->))
import System.Environment (getEnv)
import Web.Scotty

-- Needed for type declarations
import Data.Convertible.Base
--import Data.Aeson.Types.Internal

db :: String -> String
db environment = case environment of
  "prod" -> "/mnt/vol/pg-text-7.db" 
  "dev" -> "/home/jon/Code/gitenberg-scrape/pg-text-7.db"
  _ -> error "Environment must be one of 'prod' (production) or 'dev' (development)."

port :: String -> Int
port environment = case environment of
  "prod" -> 80
  "dev" -> 8000
  _ -> error "Environment must be one of 'prod' (production) or 'dev' (development)."

getByAuthor :: (Data.Convertible.Base.Convertible a SqlValue, IConnection conn) => conn -> a -> IO [[(String, SqlValue)]]
getByAuthor conn person = do
  stmt <- prepare conn "select * from meta where author like ?"
  _ <- execute stmt [toSql person]
  fetchAllRowsAL stmt

getByID :: (Convertible String SqlValue, IConnection conn) => conn -> String -> IO (Maybe [(String, SqlValue)])
getByID conn bookID = do
  stmt <- prepare conn "select * from meta where id = ?"
  _ <- execute stmt [toSql bookID]
  fetchRowAL stmt

sqlToText :: Maybe [(String, SqlValue)] -> Maybe [(String, String)]
sqlToText maybeSqlPairList = case maybeSqlPairList of
  Nothing -> Nothing
  Just sqlPairList -> Just $ map getVal sqlPairList where
    getVal (a, val) = case val of SqlNull -> (a, "NULL")
                                  _ -> (a, fromSql val :: String)

filterOutFields :: Maybe [(String, String)] -> Maybe [(String, String)]
filterOutFields maybeSqlPairList = case maybeSqlPairList of
  Nothing -> Nothing
  Just sqlPairList -> Just $ filter allowed sqlPairList where
    allowed (key, _) = take 3 key `notElem` ["am_", "gr_"]

-- textToJson :: Maybe [(String, String)] -> String
textToJson maybePairList = case maybePairList of
  Nothing -> ""
  Just pairList -> do
    let myMap = fromList pairList
    toJSON myMap

--processSql :: Maybe [(String, SqlValue)] -> Data.Aeson.Types.Internal.Value
processSql sqlPairList = textToJson $ filterOutFields $ sqlToText sqlPairList

main :: IO ()
main = do
  putStrLn "Starting server..."
  env <- read <$> getEnv "ENV"
  let portNumber = port env
      dbPath = db env
  conn <- connectSqlite3 dbPath
  scotty portNumber $ do
    get "/api/hello/:name" $ do
      name <- param "name"
      text ("hello " <> name <> "!")
    get "/api/id/:id" $ do
      bookID <- param "id"
      sql <- lift $ getByID conn (bookID::String)
      json $ processSql sql
    get "/api/author/:author" $ do
      author <- param "author"
      sql <- lift $ getByAuthor conn (author::String)
      json $ map (processSql . Just) sql
    middleware $ staticPolicy (noDots >-> addBase "static/images") -- for favicon.ico
    middleware logStdoutDev
    home >> docs >> login
