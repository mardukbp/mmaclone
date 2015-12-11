{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE FlexibleContexts #-}

module Eval
    (
    parseExpr
    ) where

import           Text.ParserCombinators.Parsec hiding (spaces)
import           Control.Monad
import Control.Applicative hiding ((<|>), many)

import DataType

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=?>@^_~#"

spaces :: Parser ()
spaces = skipMany space

spaces1 :: Parser ()
spaces1 = skipMany1 space

(<++>) a b = (++) <$> a <*> b
(<:>) a b = (:) <$> a <*> b

parsechar :: Parser Char
parsechar =
  let parseTab = '\t' <$ char 't'
      parseNewLine = '\n' <$ char 'n'
      ident = (char '\\' *>) in
    (ident $
            foldr1 (<|>)
              [char '\"', char '\\', parseTab, parseNewLine]) <|> noneOf "\""

enclose :: Parser a -> Parser b -> Parser b
enclose a = between a a

parseChar :: Parser LispVal
parseChar =
  Char <$> enclose (char '\'') parsechar

parseString :: Parser LispVal
parseString =
  String <$> enclose (char '\"') (many1 parsechar)

parseAtom :: Parser LispVal
parseAtom =
  let first = letter <|> symbol
      rest = many (letter <|> digit <|> symbol) in
    fmap check (first <:> rest)
      where check "#t" = Bool True
            check "#f" = Bool False
            check atom = Atom atom

parseNumber :: Parser LispVal
parseNumber = do
  let number = many1 digit
      plus = char '+' *> number
      minus = char '-' <:> number
      integer = plus <|> minus <|> number
      decimal = option "" $ char '.' <:> number
      expo = option "" $ oneOf "eE" <:> integer

  int <- integer
  deci <- decimal <++> expo
  return $ check int deci
    where check int "" = Number (read int)
          check int deci = Float (read (int ++ deci))

parseList :: Parser LispVal
parseList =
  let heads = endBy parseExpr spaces
      dotted = char '.' *> spaces1 *> parseExpr
      tails = option None dotted
      check h None = List h
      check h t = DottedList h t in
    liftA2 check heads tails

parseQuoted :: Parser LispVal
parseQuoted =
  let quoted = char '\'' *> parseExpr in
    (\x -> List [Atom "quote", x]) <$> quoted

parseExpr :: Parser LispVal
parseExpr = parseAtom
            <|> parseString
            <|> parseNumber
            <|> try parseChar
            <|> parseQuoted
            <|> bracket parseList
              where bracket = between (char '(') (char ')')
