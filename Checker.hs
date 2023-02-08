{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Move brackets to avoid $" #-}
module Checker (typed, showTypedExpr) where

import Parser (Expr(..), Value(..))
import Data.Map as Map
import qualified Data.Maybe
import qualified Data.List

data Type =  Free String | Quantified String | Fun Type Type | Unknown
    deriving (Show, Eq)

freeNum = Free "Num"
freeStr = Free "Str"

data ErrorMessage = ApplicationMisMatch Type Type | ArgumentMismatch Type Type | ParseError
    deriving Show

data TypedExpr = TypedVar Value Type | TypedApp [TypedExpr] Type | TypedAbs String TypedExpr Type | TypedLet String TypedExpr Type TypedExpr | TypedLetTop String TypedExpr Type | NoExpr | ErrorT ErrorMessage
    deriving Show

showType :: Type -> String
showType (Free s) = s
showType (Quantified s) = "'"++s
showType (Fun t1@(Fun _ _) t2) = "(" ++ showType t1 ++ ") -> " ++ showType t2
showType (Fun t1 t2) = showType t1 ++ " -> " ++ showType t2
showType Unknown = "_"

showTypeE t@(Fun _ _) = "(" ++ showType t ++ ")"
showTypeE t = showType t

showTypedExpr :: TypedExpr -> String
showTypedExpr (TypedAbs s e Unknown) = "(λ " ++ s ++ " . " ++ showTypedExpr e ++ "):" ++ showTypeE Unknown
showTypedExpr (TypedAbs s e t@(Fun argType _)) = "(λ " ++ s ++ " : " ++ showType argType ++ " . " ++ showTypedExpr e ++ "):" ++ showTypeE t
showTypedExpr (TypedAbs s e _) = error "Abstraction should never be inferred to be other than Unknown or Function"
showTypedExpr (TypedApp exprs t) = "(" ++ (unwords $ fmap showTypedExpr exprs) ++ "):" ++ showTypeE t
showTypedExpr (TypedVar (Num i) t) = show i ++ ":" ++ showType t
showTypedExpr (TypedVar (Str s) t) = "\"" ++ s ++ "\"" ++ ":" ++ showType t
showTypedExpr (TypedVar (Id s) t@(Fun _ _)) = s ++ ":" ++ showTypeE t
showTypedExpr (TypedVar (Id s) t) = s ++ ":" ++ showType t
showTypedExpr (TypedLet i e1 t e2) = "let " ++ i ++ " : " ++ showType t ++ " = " ++ showTypedExpr e1 ++ " in " ++ showTypedExpr e2
showTypedExpr (TypedLetTop i e t) = i ++ " : " ++ showType t ++ " = " ++ showTypedExpr e
showTypedExpr NoExpr = "\n"
showTypedExpr (ErrorT (ArgumentMismatch param arg)) = "Type error: tried to apply argument " ++ showType arg ++ " to function that takes a " ++ showType param ++ ""
showTypedExpr (ErrorT (ApplicationMisMatch ft arg)) = "Type error: tried to apply argument " ++ showType arg ++ " to non function " ++ showType ft ++ ""

type Context = Map String Type

typeOf :: TypedExpr -> Type
typeOf (TypedVar _ t) = t
typeOf (TypedApp _ t) = t
typeOf (TypedAbs _ _ t) = t
typeOf (TypedLet _ _ t _) = t
typeOf (TypedLetTop _ _ t) = t
typeOf NoExpr = Unknown
typeOf (ErrorT _) = Unknown

typeValue :: Context -> Value -> Type
typeValue _ (Num _) = freeNum
typeValue _ (Str _) = freeStr
typeValue c (Id s) = Data.Maybe.fromMaybe Unknown (Map.lookup s c)

-- syntax directed https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system#Syntax-directed_rule_system
typeExpr :: Context -> Expr -> TypedExpr
typeExpr c (Var value ta) = TypedVar value (typeValue c value)
typeExpr c (App [e1, e2] ta) =
    let typedE1 = typeExpr c e1
        typedE2 = typeExpr c e2 in
        case typeOf typedE1 of
            f@(Fun param return) -> case typeOf typedE2 of
                Unknown -> TypedApp [typedE1, typedE2] Unknown -- TODO infer
                arg -> if param == arg then TypedApp [typedE1, typedE2] return else ErrorT (ArgumentMismatch param arg)
            Unknown -> TypedApp [typedE1, typedE2] Unknown -- TODO infer
            ft -> ErrorT (ApplicationMisMatch ft (typeOf typedE2))
typeExpr c (App _ ta) = undefined
typeExpr c (Abs s ta e) = let typedE = typeExpr c e in TypedAbs s typedE (Fun Unknown (typeOf typedE)) -- TODO argtype need to get from context of typedE and unify with type assert ta
typeExpr c (Enclosed e t) =  typeExpr c e
typeExpr c (LetTop s t e) = let typedE = typeExpr c e in TypedLetTop s typedE (typeOf typedE)
typeExpr c (Let s t e1 e2) =
    let typedE1 = typeExpr c e1
        typedE2 = typeExpr c e2
    in TypedLet s typedE1 (typeOf typedE1) typedE2
-- TODO remove these
typeExpr c NewLine = NoExpr
typeExpr c (Error m) = ErrorT ParseError

typeAndAddToContext :: (Context, [TypedExpr]) -> Expr -> (Context, [TypedExpr])
typeAndAddToContext (c, texprs) e = let typedE = typeExpr c e in case typedE of
    (TypedLetTop s _ t) -> (insert s t c, texprs ++ [typedE]) -- TODO add type to context
    NoExpr -> (c, texprs ++ [NoExpr])
    _ -> error "Not a top level let at the top level"

typed exprs =
    let context = insert "print" (Fun freeStr freeStr) Map.empty in
    Data.List.foldl typeAndAddToContext (context, []) exprs



