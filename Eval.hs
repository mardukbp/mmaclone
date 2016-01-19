module Eval
    (
    eval
    ) where

import DataType
import Hier
import Number

import Control.Monad
import Control.Monad.Except
import Data.Ratio
import Data.Maybe(fromMaybe)
import Data.List(partition, genericLength, genericIndex)
-- import Control.Monad.Trans.Maybe

eval :: LispVal -> ThrowsError LispVal
eval val = do
  x1 <- eval' val
  if x1 == val then return x1 else eval x1
  -- let ans = sequence $ iterate (>>= eval') (return val)
  --     fixed (x1 : (x2 : xs))
  --       | x1 == x2 = x1
  --       | otherwise = x2 in
  --       -- | otherwise = fixed (x2 : xs) in
  --   liftM fixed ans
  --   -- undefined

eval' :: LispVal -> ThrowsError LispVal
eval' (List (v:vs)) = do
  headE <- eval v
  args <- mapM eval vs
  let old = List (headE : args)
      getFName (Atom f) = Just f
      getFName _ = Nothing
  let fun = do
        name <- getFName headE
        lookup name primitives
  case fun of
    Just f -> liftM (fromMaybe old) (f args)
    Nothing -> return old

eval' n@(Number (Rational r))
  | denominator r == 1 = return (Number $ Integer $ numerator r)
  | otherwise = return n

eval' x = return x

primitives :: [(String,[LispVal] -> Result)]
primitives = [
              -- numeric function
              ("+", numericPolop "+" plus),
              ("-", binop minus),
              ("*", numericPolop "*" times),
              ("/", binop divide),
              ("^", binop powerl),
              -- list mainpulation
              ("car", sinop car),
              ("cdr", sinop cdr),
              ("length", sinop len),
              ("part", binop part),
              -- ("")
              -- comparation
              ("<", binop lessThan),
              ("<=", binop lessEqual),
              (">", binop greaterThan),
              (">=", binop greaterEqual),
              -- ("symbol?", testHead symbolQ),
              -- ("string?", testHead stringQ),
              -- ("number?", testHead numberQ),
              -- ("quote", quoted)
              -- ("quoteient", numericBinop quot),
              ("&&", binop andl),
              ("||", binop orl),
              ("!", sinop notl)
            ]
-- quote
quoted :: [LispVal] -> ThrowsError LispVal
quoted x = return $ List (Atom "quote" : x)

-- evaluation helper function
binop :: (BinaryFun) -> [LispVal]
  -> Result
binop _ singleVal@[_] = throwError $ NumArgs 2 singleVal
binop op [a, b] = op a b
binop _ vals = throwError $ NumArgs 2 vals

sinop :: SingleFun ->
          [LispVal] -> Result
sinop op [x] = op x
sinop _ vals  = throwError $ NumArgs 1 vals

liftEval :: (LispVal -> LispVal -> LispVal) ->
              BinaryFun
liftEval f a b = return $ Just (f a b)

internalBoolOp :: (Bool ->Bool -> Bool) -> Result -> Result -> Result
internalBoolOp f a b =
  liftM2 f'' a b
    where
      f'' = liftM2 f'
      f' (Bool a) (Bool b) = Bool $ f a b

internalAnd = internalBoolOp (&&)
internalOr = internalBoolOp (||)

internalNot :: Result -> Result
internalNot a=
  liftM f'' a
    where f'' = liftM f'
          f' (Bool a) = Bool $ (not a)
---------------------------------------------------

-- Number evaluation
numericPolop :: String -> (Number -> Number -> Number) -> [LispVal]
  -> Result
numericPolop _ _ [a] = return $ Just a
numericPolop name op params = do
  let (nums,others) = partition checkNum params
      unpacked = map unpackNum nums
  let ans = foldl1 op unpacked
  return . Just $ case others of
          [] -> Number ans
          _ -> List $ Atom name : (Number ans : others)


numericBinop :: (Number -> Number -> Maybe Number) ->
  BinaryFun
numericBinop f a b
  | checkNum a && checkNum b =
    let a' = unpackNum a
        b' = unpackNum b in
      return $ fmap Number $ f a' b'
  | otherwise = return Nothing

minus, divide, powerl:: BinaryFun
minus = liftEval minus'
  where
    minus' a b = List [Atom "+", a, List [Atom "*", Number $ Integer (-1), b]]
divide = liftEval divide'
  where
    divide' a b = List [Atom "*", a, List [Atom "^", b, Number $ Integer (-1)]]

-- modl = numericBinop ((Just.). modN)
powerl = numericBinop powerN
-- ----------------------------------------



-- head test functions
testHead :: (LispVal -> Bool) -> [LispVal] -> ThrowsError LispVal
testHead test vals = return $ (Bool (all test vals))

symbolQ , stringQ, numberQ :: LispVal -> Bool

symbolQ (Atom _) = True
symbolQ _ = False

stringQ (String _) = True
stringQ _ = False

numberQ (Number _) = True
numberQ _ = False


-- list manipulation functions
len :: SingleFun
len x = return $ Just $ len' x
        where
          len' (List x) = integer $ genericLength x
          len' _ = integer 0

part :: BinaryFun
part x nv@(Number (Integer n)) = part x (List [nv])
part val (List []) = hasValue val
part val@(List x) (List (nv@(Number (Integer n)) : ns)) =
  if genericLength x <= n then throwError (PartError val nv)
                   else part (genericIndex x n) (List ns)
part x n = throwError (PartError x n)

car ,cdr :: SingleFun
car (List []) = throwError (Default "car::empty list")
car (List (x:_)) = hasValue x
car _ = noChange

cdr (List []) = throwError (Default "cdr:: empty list")
cdr (List (_:xs)) = hasValue (List xs)
cdr _ = noChange
-- ------------------------------------------


-- compare function
lessThan' , equal':: (Ord a) => a -> a -> Result
lessThan' a b = hasValue $ Bool (a < b)
equal' a b = hasValue $ Bool (a == b)

lessThan :: BinaryFun
lessThan (Number a) (Number b) = lessThan' a b
lessThan (String a) (String b) = lessThan' a b
lessThan (Bool a) (Bool b) = lessThan' a b
lessThan (Char a) (Char b) = lessThan' a b
lessThan _ _ = return Nothing

equal :: BinaryFun
equal (Number a) (Number b) = equal' a b
equal (String a) (String b) = equal' a b
equal (Bool a) (Bool b) = equal' a b
equal (Char a) (Char b) = equal' a b
equal _ _ = return Nothing

lessEqual,greaterThan,greaterEqual :: BinaryFun
lessEqual a b = internalOr (equal a b) (lessThan a b)
greaterThan = (internalNot.). lessEqual
greaterEqual = (internalNot.). lessThan
-- ----------------------------

-- logic function
logic :: (Bool -> Bool -> Bool) -> BinaryFun
logic f (Bool a) (Bool b) = hasValue $ Bool (a `f` b)
logic _ _ _ = noChange

andl, orl :: BinaryFun
andl = logic (&&)
orl = logic (||)

notl :: SingleFun
notl (Bool a) = hasValue $ (Bool $ not a)
-- --------------------------------
