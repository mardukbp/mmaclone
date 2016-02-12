{-#LANGUAGE ExistentialQuantification #-}
{-#LANGUAGE FlexibleInstances #-}
module Data.DataType where

import Control.Monad.Except
import Data.IORef
import qualified Data.Map.Strict as M
import Control.Monad.Trans.Except
import           Text.ParserCombinators.Parsec(ParseError)
import Data.List
import Data.Number.Number
import Text.Printf

-- LispVal

data LispVal =
              Number Number
            | List [LispVal]
            | Atom String
            | String String
            | Char Char
  deriving(Eq, Ord)

instance Show LispVal where
  -- show (Atom s) = s
  -- show (List s) = '(' : (unwords $ map show s) ++ ")"
  -- show (Number i) = show i
  -- show (String s) = show s
  -- show (Char c) = show c
  show = fullForm

isNull :: LispVal -> Bool
isNull (Atom "Null") = True
isNull _ = False

atomNull = Atom "Null"

isBool (Atom "True") = True
isBool (Atom "False") = True
isBool _ = False

trueQ (Atom "True") = True
trueQ _ = False

toBool True = Atom "True"
toBool False = Atom "False"
unBool (Atom "True") = True
unBool (Atom "False") = False

list ls = List $ Atom "List" : ls

fullForm :: LispVal -> String
fullForm (Atom s) = s
fullForm (List []) = ""
fullForm (List (l:ls)) =
  fullForm l ++ "[" ++ intercalate "," (map fullForm ls) ++ "]"
fullForm (Number i) = show i
fullForm (String s) = show s
fullForm (Char c) = show c

data Unpacker = forall a. Ord a => Unpacker (LispVal -> ThrowsError a)

-- data EqUnpacker = forall a. Eq a => EqUnpacker (LispVal -> ThrowsError a)

unpackNum' :: LispVal -> ThrowsError Number
unpackNum' (Number n) = return n
unpackNum' x = throwError $ TypeMismatch "number" x

unpackString' :: LispVal -> ThrowsError String
unpackString' (String s) = return s
unpackString' x = throwError $ TypeMismatch "string" x

unpackChar' :: LispVal -> ThrowsError Char
unpackChar' (Char s) = return s
unpackChar' x = throwError $ TypeMismatch "string" x

unpackBool' :: LispVal -> ThrowsError Bool
unpackBool' (Atom "True") = return True
unpackBool' (Atom "False") = return False
unpackBool' x = throwError $ TypeMismatch "string" x

unpackers :: [Unpacker]
unpackers = [Unpacker unpackNum', Unpacker unpackString',
            Unpacker unpackChar', Unpacker unpackBool']

checkNum :: LispVal -> Bool
checkNum (Number _) = True
checkNum _ = False

unpackNum :: LispVal -> Number
unpackNum = extractValue . unpackNum'

integer :: (Integral a) => a -> LispVal
integer = Number . Integer . fromIntegral

double :: Double -> LispVal
double = Number . Double
-- ------------------------------------------

-- LispError

data LispError = NumArgs String Int [LispVal]
                | NumArgs1 String
                | NumArgsN String Int Int Int
                | TypeMismatch String LispVal
                | Parser ParseError
                | BadSpecialForm String LispVal
                | NotFunction String String
                | UnboundVar String String
                | Default String
                | PartE String LispVal
                | Incomplete [LispVal]
                | SetError LispVal
                | Level LispVal


instance Show LispError where
  show (UnboundVar message varname) = message ++ ": " ++ varname
  show (BadSpecialForm message form) = message ++ ": " ++ show form
  show (NotFunction message func) = message ++ ": " ++ show func
  show (NumArgs name expected found) = name ++ "is expected " ++ show expected ++
                                      " args: found values " ++ unwordsList found
    where unwordsList = unwords . map show
  show (NumArgs1 name) = name ++ "::One or more arguments are expected"
  show (NumArgsN name l r found) = printf "%s is called with %d arguments,between %d and %d arguments are exprected" name found l r
  show (TypeMismatch expected found) = "Invalid type: expected " ++ expected
                                        ++ ", found" ++ show found
  show (Parser parseErr) = "Parse error at " ++ show parseErr

  show (Incomplete s) = show s ++ "is incomplete.More input is needed"
  show (PartE tag v) = show v ++" "++ tag
  show (Default s) = s
  show (SetError v) = "Cannot assign to object " ++ show v
  show (Level v) = show v ++ " is not a valid level specification"

type ThrowsError = Either LispError

plusError :: ThrowsError a -> ThrowsError a -> ThrowsError a
plusError (Left _) l = l
plusError a _ = a

sumError :: [ThrowsError a] -> ThrowsError a
sumError = foldr plusError (Left (Default "mzero"))


trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val

-- --------------------------------------------------

-- --------------------------------

type IOThrowsError = ExceptT LispError IO

liftThrows :: ThrowsError a -> IOThrowsError a
liftThrows (Left err) = throwError err
liftThrows (Right val) = return val

-- ---------------------------------
wrapSequence :: [LispVal] -> LispVal
wrapSequence xs = List (Atom "Sequence": xs)

applyHead,changeHead :: LispVal -> LispVal -> LispVal
applyHead h args = List [h,args]

changeHead h (List (l:ls)) = List (h:ls)
changeHead _ val = val
