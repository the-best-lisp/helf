{ 
module Parser where

import qualified Lexer as T
import qualified Concrete as C

}

%name parse
%tokentype { T.Token }
%error { parseError }

%token

id        { T.Id $$ _ }
'%abbrev' { T.Abbrev _}
'{'       { T.BrOpen _ }
'}'       { T.BrClose _ }
'['       { T.BracketOpen _ }
']'       { T.BracketClose _ }
'('       { T.PrOpen _ }
')'       { T.PrClose _ }
':'       { T.Col _ }
'.'       { T.Dot _ }
'->'      { T.Arrow _ }
'<-'      { T.RevArrow _ }
'='       { T.Eq _ }
'_'       { T.Hole _ }
type      { T.Type _ }

%%

TopLevel :: { C.Declarations }
TopLevel : Declarations { C.Declarations $1}


Declarations :: { [C.Declaration] }
Declarations 
  : {- empty -}                   { [] }
  | Declaration Declarations      { $1 : $2 }

Declaration :: { C.Declaration }
Declaration 
  : TypeSig '.'                   { $1 }
  | Defn                          { $1 }
  | '%abbrev' Defn                { $2 }
     
TypeSig :: { C.Declaration }
TypeSig : id ':' Expr             { C.TypeSig $1 $3 }

Defn :: { C.Declaration }
Defn : id ':' Expr '=' Expr '.'   { C.Defn $1 (Just $3) $5 } 
     | id '=' Expr '.'            { C.Defn $1 Nothing $3 } 

-- general form of expression
Expr :: { C.Expr }
Expr : '{' id ':' Expr '}' Expr   { C.Pi $2 $4 $6 }  
     | Expr1 '->' Expr            { C.Fun $1 $3 }
     | Expr1                      { $1 }

-- perform applications
Expr1 :: { C.Expr }
Expr1 : Apps                      { if length $1 == 1 then (head $1) else C.Apps (reverse $1) }

-- gather applications
Apps :: { [C.Expr] }
Apps : Atom                       { [$1] }
     | Apps Atom                  { $2 : $1 }

-- atoms
Atom :: { C.Expr }
Atom : type                       { C.Type }
     | id                         { C.Ident $1}
     | '(' Expr ')'               { $2 }
     | '[' id ':' Expr ']' Expr   { C.Lam $2 (Just $4) $6 } 
     | '[' id ']' Expr            { C.Lam $2 Nothing $4 }
{-
     | '_'                        { C.Unknown }
-}

{

parseError :: [T.Token] -> a
parseError [] = error "Parse error at EOF"
parseError (x : xs) = error ("Parse error at token " ++ T.prettyTok x) 

}

 



