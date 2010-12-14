module OrderedSubst where

import Prelude hiding (pi)

import Control.Applicative
import Control.Monad.Error
import Control.Monad.Reader

import Control.Monad.State

import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe

import Abstract as A
import Value
import TypeCheck
-- import Context
import Signature
import Util

import DataStructure as DS
import DatastrucImplementations.DS_SimpleDynArray (DynArray)
import DatastrucImplementations.DS_List (List)
import DatastrucImplementations.DynArrayInstance

-- "ordered" Expressions

-- type OName = String
type OType = OExpr


data OExpr
  = OCon Name
  | ODef Name
  | O
  | OApp OExpr Int OExpr
  | OAbs [Int] OExpr
  | OPi  OType OType
  | OType
--  | OKind -- only internally
    deriving (Eq,Ord,Show)

-- Values

type Var = Int


data Head 
  = HVar Var      -- (typed) variable 
  | HCon A.Name   -- (typed) constructor
  deriving (Eq,Ord,Show)

data Val 
  = Ne   Head Val [Val]     -- x^a vs^-1 | c^a vs^-1   last argument first in list!
  | Sort Sort               -- s
  | Clos OExpr OSubst       -- (\xe) rho
  | Fun  Val  Val           -- Pi a ((\xe)rho)


instance Value Head Val where
  typ  = Sort Type
  kind = Sort Kind
  freeVar h t = Ne h t []

  tyView (Fun a b) = VPi a b
  tyView (Sort s)  = VSort s
  tyView _         = VBase
 
  tmView (Ne h t vs) = VNe h t (reverse vs) -- see above: last argument first in list!
  tmView _           = VVal
  

---------------

-- ordered substitution

type OSubst = DynArray Val

type EvalM = Reader (MapSig Val)


-- Evaluation
apply :: Val -> Val -> EvalM Val
-- apply (K w) _ _ = w
apply (Ne head t vs) v = return $ Ne head t (v:vs)
apply (Clos (OAbs klist oe) osubst) v = OrderedSubst.evaluate oe (multiinsert v klist osubst)

evaluate :: OExpr -> OSubst -> EvalM Val
evaluate e osubst = case e of
    OCon x         -> symbType . sigLookup' x <$> ask
    ODef x         -> symbDef  . sigLookup' x <$> ask
    O              -> return $ DS.get osubst 0
    OApp oe1 k oe2 -> let (osubst1, osubst2) = split k osubst 
                      in Util.appM2 OrderedSubst.apply (OrderedSubst.evaluate oe1 osubst1) (OrderedSubst.evaluate oe2 osubst2)
    OAbs _ _       -> return $ Clos e osubst
    -- TODO: add OPi !
    -- OPi ty1 ty2    -> Fun (OrderedSubst.evaluate ty1 osubst) (Clos ty2 osubst)
    OType          -> return $ typ
    -- OKind          -> kind
    
    
-- hConst x = Ne (HConst x) []
hConst :: A.Name -> Val -> Val
hConst x t = Ne (HCon x) t []




{-- Closures:
-- Type checking monad

data Context = Context
  { level  :: Int
  , tyEnv  :: Env
  , valEnv :: Env
  }

emptyContext :: Context
emptyContext = Context 0 Map.empty Map.empty

type Err = Either String
type TCM = ReaderT Context Err

instance TypeCheck Val TCM where  

  app f v = return $ apply f v
  
  eval e = evaluate e <$> asks valEnv 
    
  addBind x a cont = do
    Context level tyEnv valEnv <- ask
    let xv   = freeVar level a
    let cxt' = Context 
                 (level + 1)
                 (Map.insert x a tyEnv)
                 (Map.insert x xv valEnv)
    local (const cxt') (cont xv)

  addBind' _ a cont = do
    l <- asks level
    let xv = freeVar l a
    local (\ cxt -> cxt { level = level cxt + 1 }) (cont xv)

  lookupVar x = do
    gamma <- asks tyEnv
    case Map.lookup x gamma of
      Just t  -> return t
      Nothing -> fail $ "unbound variable " ++ x 

-}


--------------------------------------------------------------------------------------
---- any possibility to hide this? (it just serves the transformation below)
data (Ord name) => LocBoundList name = LBL {lblsize :: Int, bList :: (Map name Int)}
lbl_empty = LBL 0 (Map.empty)

--lblsize :: (Ord name) => LocBoundList name -> Int
--lblsize (LBL k name) = k

--bList :: (Ord name) => LocBoundList name -> Map name Int
--bList (LBL _ m) = m

insert :: (Ord name) => name -> LocBoundList name -> LocBoundList name
insert n (LBL k m) = LBL (k+1) (Map.insert n k m) -- note that it does NOT matter whether or not n already had been a key before!

type LambdaLists = [[Int]]
incrKaddZero :: Int -> LambdaLists -> LambdaLists
incrKaddZero 0 (l:ll) = (0:l):ll
incrKaddZero (k+1) ((i:l):ll) = ((i+1):l) : incrKaddZero k ll


-- transform (monadic version)
--type Transform a = LocBoundList Name -> LambdaLists -> (a, LambdaLists)
type Transform = ReaderT (LocBoundList Name) (State LambdaLists)

transform :: Expr -> OExpr
transform e = snd $ trans e `runReaderT` lbl_empty `evalState` [] where
  
  trans :: Expr -> Transform (Int, OExpr)
  trans (Ident ident) = case ident of
    Var x -> do
      lbl <- ask
      case Map.lookup x (bList lbl) of
        Just k -> do
          {- ll <- get
          put $ incrKaddZero (lblsize lbl - 1 - k) ll  -}
          modify $ incrKaddZero (lblsize lbl - 1 - k)
          return (1, O)
        Nothing -> fail $ "variable " ++ show x ++ " is not bound"
    Con x -> return (0, OCon x)
    Def x -> return (0, ODef x)
  
  {-
    trans (Apps (e:es)) = 
    let
    trShortApp :: Expr -> Expr -> OExpr
    trShortApp e1 e2 = do
      (i1, oexpr1) <- trans e1
      (i2, oexpr2) <- trans e2
      return (i1 + i2, OApp oexpr1 i2 oexpr2)
    in
    foldl trShortApp e es
  -}
  
  trans (App e1 e2) = do
    (i1, oexpr1) <- trans e1
    (i2, oexpr2) <- trans e2
    return (i1 + i2, OApp oexpr1 i2 oexpr2)
  
  trans (Lam x mty e) = do -- !! Maybe Type !!
    modify ((:) [0]) 
    (i, oexpr) <- local (OrderedSubst.insert x) $ trans e
    (l':ll')   <- Control.Monad.State.get
    put $ ll'
    return (i + 1 - (length l'), OAbs (reverse $ tail l') oexpr) 
  
  trans (Pi name ty1 ty2) = case name of
    Just n -> do
      (i1, oexpr1) <- trans ty1
      (i2, oexpr2) <- trans $ Lam n Nothing ty2 -- Nothing?
      return (i1+i2, OPi oexpr1 oexpr2)
    Nothing -> do
      (i1, oexpr1) <- trans ty1
      (i2, oexpr2) <- trans ty2
      return (i1+i2, OPi oexpr1 $ OAbs [] oexpr2)
  
  -- trans (Sort Type) = return (0, OType)
  -- trans (Sort Kind) = return (0, OKind)

{- TODO delete this
---
type Type = Expr
data Expr
  = Ident Ident
  | Typ                           -- ^ type
  | Pi    (Maybe Name) Type Type  -- ^ A -> B or {x:A} B
  | Lam   Name (Maybe Type) Expr  -- ^ [x:A] E or [x]E
  | App   Expr Expr               -- ^ E1 E2 
  deriving (Show)

data Ident 
  = Var { name :: Name }          -- ^ locally bound identifier
  | Con { name :: Name }          -- ^ declared constant
  | Def { name :: Name }          -- ^ defined identifier
  deriving (Show)
---
-}



-- transform (original version, not updated)
{-
transform0 :: Expr -> OExpr
transform0 e =
  let 
  
  -- takes: an expression e, the list containing bound variable names which is valid for e, the binding lists of the lambdas 'above' e).
  -- returns the build expression's number of "not-yet-bound" bound variables (i.e. number of O which are not bound in the returned 'subexpression') and, after that, all the modified information in the same order as it was taken
  trans :: Expr -> (LocBoundList Name) -> LambdaLists -> (Int, OExpr, LambdaLists) -- why would we need the new LocBoundList ??
  trans (Var x) lbl ll = case Map.lookup x (bList lbl) of
    Just k  -> (1, O, incrKaddZero ((lblsize lbl) - 1 - k) ll)
    Nothing -> (0, OVarFree x, ll)
  trans (App e1 e2) lbl ll = 
    let
    (i1, oexpr1, ll1) = trans e1 lbl ll
    (i2, oexpr2, ll2) = trans e2 lbl ll1
    in 
    (i1+i2, OApp oexpr1 i2 oexpr2, ll2)
  trans (Abs x e) lbl ll = 
    let
    (i, oexpr, l':ll') = trans e (OrderedSubst.insert x lbl) ([0]:ll) 
    l'' = reverse (tail l') -- TODO: check whether reversing is really necessary!
    ibound = length l''
    in
    (i - ibound, OAbs l'' oexpr, ll')

  -- TODO: check whether the following is correct!

  trans (Pi name ty1 ty2) lbl ll = 
    case name of
      Just n -> 
        let
        (i1, oexpr1, ll1) = trans ty1 lbl ll
        (i2, oexpr2, ll2) = trans (Abs n ty2) lbl ll1 -- TODO: correct??
        in
        (i1+i2, OPi oexpr1 oexpr2, ll2)
      Nothing ->
        let
        (i1, oexpr1, ll1) = trans ty1 lbl ll
        (i2, oexpr2, ll2) = trans ty2 lbl ll1 -- same as above
        oexpr2' = OAbs [] oexpr2
        in
        (i1+i2, OPi oexpr1 oexpr2', ll2)
  trans (Sort Type) lbl ll = (0, OType, ll)
  trans (Sort Kind) lbl ll = (0, OKind, ll)
  
  (i, oexpr, ll) = trans e lbl_empty []
  in 
  oexpr
-}

-----------------------------------------------------------------------------
-- Tests (not updated yet)

{-
test = Abs "1" $ Abs "2" $ Abs "3" $ Abs "4" $ Abs "5" $ Abs "6" $ Var "3"

ty = Sort Type
pi x = Pi (Just x)

eid = Abs "A" $ Abs "x" $ Var "x"
tid = pi "A" ty $ pi "x" (Var "A") $ Var "A"

arrow a b = Pi Nothing a b

tnat = pi "A" ty $ 
         pi "zero" (Var "A") $ 
         pi "suc"  (Var "A" `arrow` Var "A") $
           Var "A" 

ezero  = Abs "A" $ Abs "zero" $ Abs "suc" $ Var "zero"
-- problem: esuc is not a nf
esuc n = Abs "A" $ Abs "zero" $ Abs "suc" $ Var "suc" `App` 
          (n `App` Var "A" `App` Var "zero" `App` Var "suc")  

enat e =  Abs "A" $ Abs "zero" $ Abs "suc" $ e
enats = map enat $ iterate (App (Var "suc")) (Var "zero")
e2 = enats !! 2

transTest = transform test -- etc
-}