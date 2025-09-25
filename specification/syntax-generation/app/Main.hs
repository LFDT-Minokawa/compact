-- This file is part of Compact.
-- Copyright (C) 2025 Midnight Foundation
-- SPDX-License-Identifier: Apache-2.0
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
-- 	http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.


-- | Module Main.hs
--
-- Author: Cas van der Rest 
--
-- This module defines a conversion from Nanopass IRs, represented as
-- JSON serialized S-expressions, to a mutually-recursive family of
-- data types in Agda. This way, Agda specifications of Compact and
-- its intermediate representations can use the same abstract syntax
-- definitions as the compiler uses interngally.
-- 
-- By automatically updating the compiler-generated syntax files, we
-- can thus force synchronization between the implementation and
-- specification of Compact.
-- 
--
-- Usage:
--
-- As of right now, we still have to extract syntax definitions
-- manually from the compiler, and convert them manually. Assuming a
-- compiler-generated syntax definition is stored in JSON format in
-- `Syntax/json/<IR NAME>.json`, we convert it to an Agda syntax
-- defintion as follows:
-- 
--   $ ghci IR.hs
--   ghci> convert <IR NAME>
--
-- If the conversion is succesful, this creates an Agda file in the
-- following location: `Syntax/Generated/<IR NAME>.agda`.
--
-- For example, to generate Agda syntax for the `Lsrc` IR:
--
--   $ ghci IR.sh
--   ghci> convert "Lsrc"
--
-- This assumes that `./Syntax/json/Lsrc.json` exists, and will write
-- the result to `./Syntax/Generated/Lsrc.agda`. 

module Main where

import Data.Tuple (swap) 
import Data.List qualified as L
import Data.Text qualified as T
import Data.Vector qualified as V
import Data.Map qualified as Map 
import Data.Time (getCurrentTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Char qualified as Char
import Data.Aeson
import GHC.Generics

import Control.Monad.Except
import Control.Monad.State
import Control.Monad.Identity
import Control.Monad.Writer
import Control.Monad.Reader

import System.Environment

-- | Represents a syntactic sort (or, nonterminal). 
data Sort = Sort
  { name         :: String
  , constructors :: [Cons]
  } deriving (Generic , Show)

-- | Represents a constructor (or, production rule). 
data Cons = Cons
  { consname :: String
  , args     :: [Argument]
  } deriving (Generic , Show)

-- | Represents a constuctor argument. 
data Argument = Argument
  { sort  :: String
  } deriving (Generic , Show , Eq)

-- | Compiler languages are defined as a family of sorts. 
data IR = IR
  { irName          :: String
  , compilerVersion :: String
  , languageVersion :: String
  , sorts           :: [Sort]
  } deriving (Generic , Show) 

instance ToJSON Argument where 
instance ToJSON Cons where
instance ToJSON Sort where
instance ToJSON IR where

-- | Configures the location of JSON source files
read_path :: FilePath
read_path = "./Syntax/json/"

-- | Configures the location of generated Agda syntax files
write_path :: FilePath
write_path = "./Syntax/Generated"

infixr 8 :.: 
data SExpr = Atom String
           | SExpr :.: SExpr
           | Nil 
           deriving Show 


-- | The type of errors thrown during generation/conversion. For now,
-- it's just a string describing the error that occured
type Err = String

-- | Contextual information that should be available during conversion.
-- The context keeps track of 3 things:
--
-- 1. A mapping of metavariables to sort names, 
-- 2. a list of known terminals used in the grammar, and
-- 3. a list of constructor names, local to a sort
--
data Context = Context
  { metavars  :: Map.Map String String
  , terminals :: [String]
  , connames  :: [String] 
  }
  deriving Show

-- | Checks if a given name is a known terminal in the current
-- context.
isTerminal :: MonadState Context m => String -> m Bool
isTerminal str = do
  ctx <- get
  return (str `elem` terminals ctx)

-- | Register a new metavariable mapping in the context. 
registerMetavar :: MonadState Context m => String -> String -> m ()
registerMetavar k v = do
  ctx <- get
  put (Context (Map.insert k v (metavars ctx)) (terminals ctx) (connames ctx)) 

-- | Register a new constructor name in the context. 
addCName :: MonadState Context m => String -> m ()
addCName n = do
  ctx <- get
  put (Context (metavars ctx) (terminals ctx) (n:connames ctx))

-- | Clear list of known constructors 
forgetCNames :: MonadState Context m => m ()
forgetCNames = do
  ctx <- get 
  put (Context (metavars ctx) (terminals ctx) [])

-- | Reads a JSON value as an S expression 
jsonToSExpr :: MonadError Err m =>  Value -> m SExpr 
jsonToSExpr (String x)  = return $ Atom (T.unpack x)
jsonToSExpr (Array arr) = case V.toList arr of
  []     -> return Nil 
  (x:xs) -> do
    l <- jsonToSExpr x
    r <- jsonToSExpr (Array (V.fromList xs))
    return (l :.: r)
jsonToSExpr _ = throwError $
  "Only arrays and strings can be represented as S expressions." 

-- | Converts an S-expression generated from a NanoPass IR to an IR as defined above.
sExprToIR :: (MonadState Context m , MonadError Err m) => SExpr -> m IR 
sExprToIR ((Atom "Compiler version" :.: (Atom compilerVersion :.: Nil)) :.: (Atom "Language version" :.: (Atom languageVersion :.: Nil)) :.: (Atom "define-language" :.: (Atom irName :.: s))) =
   IR irName compilerVersion languageVersion <$> sExprToSorts s
sExprToIr _ = throwError $
  "Failed to read IR metadata."

-- | Converts an S-expression to a constructor argument.
--
-- Sometimes, a list of arguments is nested, in which case we
-- "flatten" the nested structure in to a list. For example, the
-- following production in the `Ltypes` IR:
--
--   `(tcontract src contract-name (elt-name* pure-dcl* (type** ...) type*) ...)`
--
-- TODO: verify that this is indeed how the production rule should be
-- converted to Agda.
-- 
convertArg :: (MonadState  Context m , MonadError Err m) => SExpr -> m [Argument]
convertArg (Atom aname)                        = return ([Argument aname])
convertArg (Atom aname :.: Atom "..." :.: Nil) = return ([Argument aname])
convertArg s                                   = sExprToArgs s 

-- | Converts an S-expression to a list of arguments. 
sExprToArgs :: (MonadState  Context m , MonadError Err m) => SExpr -> m [Argument]
sExprToArgs (Atom x)   = throwError $
   "Found an atom while attempting to convert S expression to argument"
sExprToArgs Nil        = return []
sExprToArgs (s :.: ss) = (++) <$> convertArg s <*> sExprToArgs ss    

-- | Converts an S-expression to a list of constructors. 
sExprToConstructors :: (MonadState  Context m , MonadError Err m) => SExpr -> m [Cons]
sExprToConstructors (Atom x)   = throwError
  "Found an atom while attempting to convert S expression to constructor"
sExprToConstructors Nil        = return []
sExprToConstructors (s :.: ss) = do
  x <- convertCons s
  xs <- sExprToConstructors ss
  return (x:xs)
  where
    -- | Converts an S-expression to a constructor. 
    convertCons :: (MonadState  Context m , MonadError Err m) => SExpr -> m Cons
    convertCons (Atom cname :.: args) = do

      -- Check if the head of the list is a known terminal. 
      x <- isTerminal cname
      
      -- If the first atom in the list is a terminal, we treat it
      -- as an unnamed constructor 
      if x then
        Cons
          <$> return "unnamed"
          <*> sExprToArgs (Atom cname :.: args)
          
      -- Otherwise, use the provided name. However, we'll add a suffix if
      -- the same constructor name has been used before in the current
      -- sort definition. 
      else
        do usedNames <- connames <$> get
           let suffix =
                 if cname `elem` usedNames then
                   show (length $ filter (==cname) usedNames)
                 else
                   ""
           addCName cname 
           Cons
            <$> return (cname <> suffix) 
            <*> sExprToArgs args
    convertCons (Atom cname)          = return $ Cons cname [] 
    convertCons s                     = throwError (show s) 


-- | Converts an S-expression to a list of terminals.
--
-- Nanopass IRs contain some metadata about terminals used in the
-- grammar. This function interprets that metadata.
sExprToTerminals :: MonadError Err m =>  SExpr -> m [String]
sExprToTerminals (Atom "terminals" :.: ts) = convertTerminals ts
  where
    -- | Converts an S-expression to a list of terminals. 
    convertSymbols :: (MonadError Err m) => SExpr -> m [String] 
    convertSymbols (Atom tm :.: ts) =
      (:)
        <$> return tm
        <*> convertSymbols ts 
    convertSymbols Nil              = return []
    convertSymbols _                = throwError $
      "Unexpected structure of S expression while attempting to convert terminal list" 

    -- | Converts an S-expression to a named terminal grouping. 
    convertCls :: (MonadError Err m) => SExpr -> m [String]
    convertCls (Atom cls :.: ts :.: Nil) = convertSymbols ts 
    convertCls _                         = throwError $
      "Unexpected structure of S expression while attempting to convert terminal grouping"  

    -- | Converts an S-expression into terminal metadata. 
    convertTerminals :: (MonadError Err m) => SExpr -> m [String]
    convertTerminals (Atom x)   = throwError $
      "Found an atom while attempting to convert S expression to terminal list"
    convertTerminals Nil        = return []
    convertTerminals (s :.: ss) =
      (++)
        <$> convertCls s
        <*> convertTerminals ss
       
sExprToTerminals _                         = 
  throwError "Unexpected structure of S expression while converting terminal section" 

-- | Converts an S-expression into a family of Sorts. As part of this
-- process, metadat about terminals is converted as well.
sExprToSorts :: (MonadState Context m , MonadError Err m) => SExpr -> m [Sort]
sExprToSorts (s :.: terminals :.: sorts) = do
  ctx <- get
  ts  <- sExprToTerminals terminals
  put ( Context
          { metavars  = metavars ctx
          , terminals = ts
          , connames  = connames ctx
          } )   
  convertSorts sorts
  
  where
    convertSort :: (MonadState Context m , MonadError Err m) => SExpr -> m (Sort)
    convertSort (Atom sname :.: (Atom metavar :.: Nil) :.: constructors) = do
      registerMetavar metavar sname
      s <- Sort
        <$> return sname
        <*> sExprToConstructors constructors
      forgetCNames
      return s
    
    convertSorts :: (MonadState Context m , MonadError Err m) => SExpr -> m [Sort]
    convertSorts (Atom x)   = throwError $
      "Found an atom while attempting to convert S expression to Sort"
    convertSorts Nil        = return []
    convertSorts (s :.: ss) =
      (:)
        <$> convertSort  s
        <*> convertSorts ss
        
sExprToSorts _ = throwError $
  "Found an S expression with unexpected structure when attempting to convert to IR"

-- | filter arguments from an IR representation based on the given list of predicates 
dropArgs :: [Argument -> Bool] -> IR -> IR
dropArgs ps (IR iname cv lv sorts) = IR iname cv lv (map dropFromSort sorts)
  where
    dropFromCons :: Cons -> Cons
    dropFromCons (Cons cname args) =
      Cons cname (filter (not . or . flip map ps . flip ($)) args)
    
    dropFromSort :: Sort -> Sort
    dropFromSort (Sort sname cs) =
      Sort sname (map dropFromCons cs)

-- | Transform arguments from an IR representation based on the given
--   list of transformations
transformArgs :: [Argument -> Argument] -> IR -> IR
transformArgs ts (IR iname cv lv sorts) =
  IR iname cv lv (map transformSort sorts)
  where
    transformCons :: Cons -> Cons
    transformCons (Cons cname args) =
      Cons cname (map (foldr (.) id ts) args)

    transformSort :: Sort -> Sort
    transformSort (Sort sname cs) =
      Sort sname (map transformCons cs)

-- | Transform constructors in an IR representation based on the given
-- list of transformations. 
transformCons :: [Cons -> Cons] -> IR -> IR
transformCons ts (IR iname cv lv sorts) =
  IR iname cv lv (map transformSort sorts)
  where
    transformSort :: Sort -> Sort
    transformSort (Sort sname cs) =
      Sort sname (map (foldr (.) id ts) cs) 

-- | Attempts to load a file in the given path, and interpret its
-- contents as JSON. 
loadJSON :: FilePath -> IO (Either String Value)
loadJSON = eitherDecodeFileStrict

-- | Finds the metavariable string for a given sort name in a context.
lookupSortName :: Context -> String -> Maybe String
lookupSortName ctx str = Map.lookup str (Map.fromList $ map swap $ Map.toList $ metavars ctx)

-- | Finds a metavariable in a context, accounting common suffixes. 
lookupMetavar :: Context -> String -> Maybe String
lookupMetavar ctx str = let x = last str in
  if Char.isDigit x || x == '*' || x == '^' then 
    (++[x]) <$> Map.lookup (init str) (metavars ctx) 
  else
    Map.lookup str (metavars ctx) 

-- | A mapping of terminals to Agda types, for terminals defined
-- *OUTSIDE* the current IR.
terms :: [(String , String)]
terms =
  [ ("opaque-type"  , "String")
  , ("datum"        , "ℕ ⊎ Bool")
  , ("pure-dcl"     , "Bool")
  , ("mesg"         , "String")
  , ("file"         , "String")
  , ("prefix"       , "String")
  , ("nat"          , "ℕ")
  , ("adt-formal"   , "⊤") --- Q: what is this?
  , ("mbits"        , "⊤") --- Q: what is this?
  , ("native-entry" , "⊤") --- Q: what is this?  
  ] 

main :: IO ()
main = do
  args <- getArgs
  case args of
    (ir_name:_) -> do 
      putStrLn $ "=== Generating Agda syntax definition for \"" <> ir_name <> "\" ===" 
      convert ir_name
    _ -> putStrLn "No IR name specified, exiting ..." 

-- | Attempt to convert the given IR into an Agda syntax file.
--
-- This is the entry point you should use when running the tool using
-- GHCI.
convert :: String -> IO ()
convert name = do

  -- Tries to load 
  --
  -- TODO: should naming/location of JSON representations be
  -- configurable?
  let json_path = "../src/Syntax/json/" <> name <> ".json"
  putStrLn $ " -> Reading JSON from " <> json_path <> "."
  result <- loadJSON json_path

  
  case result of 
    (Left err)  -> do
      putStrLn "ERROR -> Failed to read JSON input."
      putStrLn err
    (Right val) -> do
      putStrLn " -> Parsing IR." 
      case readIR val of
        (Left err)  -> do
          putStrLn "ERROR -> Faild to convert JSON to IR"
          putStrLn err
        (Right (ir , ctx)) -> do
          
          -- Ready the IR for conversion to Agda by applying
          -- constructor and argument transformations.
          putStrLn " -> Applying argument and constructor transformations."
          let ir' =
                ( transformCons (consTransform ctx)
                  $ transformArgs (argTransform ctx)
                  $ dropArgs argFilters ir
                )

          -- Generate an Agda module containing the syntax definition.
          putStrLn " -> Generating Agda module."
          generateAgdaModule ctx ir'
          putStrLn "Done." 
      
  where
    -- | Tries to read an IR from the given JSON value. 
    readIR :: Value -> Either Err (IR , Context) 
    readIR value =
      runIdentity $
        runExceptT $
          runStateT
            (jsonToSExpr value >>= sExprToIR)
            (Context Map.empty [] []) 

    -- Defines which "arguments" should be filtered from the IR after
    -- reading the S-expression.
    argFilters :: [Argument -> Bool]
    argFilters = 
      [ (==) "src" . sort 
      , (==) "..." . sort 
      ]

    -- Defines which transformations oucht to be applied to the argument names
    -- **after** filtering
    --
    -- Transformations are applied top-to-bottom; it's up to us to
    -- ensure they're applied in the right order if they don't commute
    -- (which they likely will)
    argTransform :: Context -> [Argument -> Argument]
    argTransform ctx = reverse $
      
      [ -- Lookup metavariables and replace with corresponding sort name
        \arg@(Argument str) ->
          maybe arg Argument (lookupMetavar ctx str)

        -- Replace arguments with postfix '?' with `Bool` 
      , \arg@(Argument str) ->
          if last str == '?' then
            Argument "Bool"
          else
            arg

        -- Mark arguments that contain the word "name" as strings 
      , \arg@(Argument str) ->
          if "name" `L.isInfixOf` str then
            case last str of
              '*' -> Argument "List String"
              '^' -> Argument "Maybe String"
              _   -> Argument "String"
          else
            arg
      
        -- Mark arguments ending with '*' as lists
      , \arg@(Argument str) ->
          if last str == '*' then
            Argument ("List " ++ init str)
          else
            if last str == '*' && last (init str) == '*' then
              Argument ("List (List " ++ init (init str) ++ ")")
            else
              arg

        -- Mark arguments ending with '^' as Optional
      , \arg@(Argument str) ->
          if last str == '^' then
            Argument ("Maybe " ++ init str)
          else
            arg
      
        -- Drop postfix numbering, e.g., in `expr1` 
      , \arg@(Argument str) ->
          if Char.isDigit (last str) then
            Argument (init str)
          else
            arg

         -- Replace known terminals 
      ,  \arg@(Argument str) ->
           Argument $ foldr (uncurry replace) str terms   
      ] 
      
    consTransform :: Context -> [Cons -> Cons]
    consTransform ctx = reverse $

      [ -- Add a prime to the names of constructors that are protected names in agda
        \cons@(Cons cname args) ->
          if cname `elem` protectedNames then
            Cons (cname <> "′") args
          else
            cons

        -- For constructors whose name is a meta-variable
        -- (non-terminal), add an extra argument of the type that the
        -- variable resolves to. 
      , \cons@(Cons cname args) ->
          maybe cons (\n -> Cons ("`" <> cname) (Argument n:args)) (lookupMetavar ctx cname)

        -- For constructors whose name is known terminal, add an extra
        -- argument of the type that the terminal corresponds to
      , \cons@(Cons cname args) ->
          maybe cons (\n -> Cons cname (Argument n:args)) (lookup cname terms) 
          
      ]
      where
        protectedNames :: [String]
        protectedNames =
          [ "constructor"
          , "quote"
          , "import"
          , "module"
          , "="
          , "pattern" 
          ]

-- Replace a substring in a string
replace :: String -> String -> String -> String
replace old new str = T.unpack $ T.replace (T.pack old) (T.pack new) (T.pack str)
       
type AgdaCode = String

-- | Emits a single line of code 
line ::
  ( MonadWriter AgdaCode m
  , MonadState Int m 
  ) => AgdaCode -> m ()
line code = do
  l <- get
  tell $ (replicate (2*l) ' ') <> code <> "\n" 

-- | automatically prepends all calls to the `line` function in the
-- given computation
indent ::
  (  MonadWriter AgdaCode m
  , MonadState Int m
  ) => m () -> m ()
indent m = do
  l <- get
  put (l + 1) 
  m 
  put l 

-- | Outputs the given constructor as Agda code. 
constructorToAgda ::
  ( MonadReader String m
  , MonadWriter AgdaCode m
  , MonadState Int m 
  ) => Cons -> m ()
constructorToAgda cons = do
  dt   <- ask
  let as = map sort (args cons)
  let ty = foldr (\a t -> a <> " -> " <> t) "" as  
  line $ consname cons <> " : " <> ty <> dt 

-- | Outputs the given sort as Agda code. 
sortToAgda ::
  ( MonadWriter AgdaCode m
  , MonadState Int m
  , MonadReader Context m
  , MonadError Err m 
  ) => Sort -> m ()
sortToAgda sort = do
  line ""
  line $ "-- Sort: " <> name sort 
  line $ "data " <> name sort <> " : Set where"
  indent $
    mapM_ (flip runReaderT (name sort) . constructorToAgda) (constructors sort)
  line ""
  line "variable"
  indent $ do 
    ctx  <- ask
    let mmvar = lookupSortName ctx (name sort)
    case mmvar of
      Just mvar -> do 
        line $ L.intercalate " " (variations mvar)  <> " : " <> name sort
        line $ mvar <> "∗ : List " <> name sort
        line $ mvar <> "^ : Maybe " <> name sort 
      Nothing   -> throwError $ "Unknown sort: " <> name sort
    line ""

  where
    variations :: String -> [String]
    variations x = [ x , x <> "₁" , x <> "₂" , x <> "₃" , x <> "′" ] 

-- | Convert an Intermediate representation to Agda. 
irToAgda ::
  ( MonadWriter String m
  , MonadState Int m
  , MonadError Err m
  , MonadReader Context m 
  ) => IR -> m () 
irToAgda ir = do
  line  $ "module Syntax.Generated." <> irName ir <> " where" 
  indent $ do 
    line "mutual" 
    indent $ do
      mapM_ sortToAgda (sorts ir)
    line $ irName ir <> " : " <> "List (Set × String)"
    line $ irName ir <> " = "
    indent $ do
      mapM_ (\sort -> do
        ctx <- ask
        let mmvar = lookupSortName ctx (name sort)
        case mmvar of
          Just mvar -> line $ "(" <> name sort <> " , \"" <> mvar <> "\") ∷"
          Nothing   ->  throwError $ "Unknown sort: " <> name sort
        ) (sorts ir) 
      line "[]"

-- | Generates an Agda module containing the given IR. 
generateAgdaModule :: Context -> IR -> IO ()
generateAgdaModule ctx ir = do
  time <- getCurrentTime
  let timeStr  = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" time
  let hdr =    "-- ***\n" 
            <> "-- *** The definitions in this file were automatically generated from the `"
               <> irName ir <> "` Nanopass IR.\n"
            <> "-- *** \n" 
            <> "-- *** TIMESTAMP: " <> timeStr <> " \n"
            <> "-- *** \n"
            <> "-- *** Compiler version: " <> compilerVersion ir <> "\n" 
            <> "-- *** Language version: " <> languageVersion ir <> "\n"
            <> "\n"
            <> "{-# OPTIONS --safe --without-K #-}"
            <> "\n"
            <> "open import Data.String  using (String) \n"
            <> "open import Data.List    using (List; [] ; _∷_) \n"
            <> "open import Data.Bool    using (Bool)\n"
            <> "open import Data.Nat     using (ℕ)\n"
            <> "open import Data.Sum     using (_⊎_)\n"
            <> "open import Data.Maybe   using (Maybe)\n"
            <> "open import Data.Product using (_×_ ; _,_)\n"
            <> "open import Data.Unit    using (⊤)\n" 
            <> "import Agda.Builtin.Reflection as Reflection"
            <> "\n" 
            <> "\n" 
  let res = runIdentity (flip runReaderT ctx $ runExceptT $ runWriterT $ runStateT (irToAgda ir) 0)
  case res of
    Left err                -> do
      putStrLn "Error while generating Agda code: "
      putStrLn err 
    Right ((() , _) , code) -> do
      let agda_path = ("../src/Syntax/Generated/" <> irName ir <> ".agda")
      putStrLn $ " -> Writing module to \"" <> agda_path <> "\"."
      writeFile agda_path (hdr <> code) 

{- 

LEGACY 

-- We define equivalence of IRs as follows:
--
-- IRs are essentialy defined as a list of sorts. We say that two IRs
-- are equivalent if they (1) define the same sorts, up to permutation,
-- and (2) each matching sort is equivalent.
--
-- Similarly, sorts are defined as lists of constructors. We say that
-- two sorts are equivalent if they (1) define the same constructors,
-- up to permutation, and (2) each matching constructor is equivalent.
--
-- Constructors are defined as lists of arguments. We say that two
-- constructors are equivalent if they have the same arguments, up to
-- permutation.
--
-- Comparison between IRs is mostly nominal, which requires some
-- pre-processing before we can compare the definitions emitted
-- respectively from the compiler and the specification. 
--

-- | Compares two sorts for equivalence, throwing an error if a
--   deiscrepancy is found.
compareSort :: MonadError Err m => Sort -> Sort -> m ()
compareSort s1 s2 = return () 

-- | Compares two IRs for equivalence, throwing an error if a
--   discrepancy is found.
compareIR :: MonadError Err m => IR -> IR -> m () 
compareIR ir1 ir2 = do
  if irName ir1 == irName ir2 then
    let snames1 = map name (sorts ir1) in
    let snames2 = map name (sorts ir2) in

    -- Check if both IRs consist of the same sorts (up to permutation) 
    if L.sort snames1 == L.sort snames2 then
      mapM_ (\n -> do
         -- IRs pointwise by comparing sorts 
         s1 <- lookupSort n ir1
         s2 <- lookupSort n ir2
         compareSort s1 s2 
       ) snames1 
    else
      throwError $
        "Sort mismatch while comparing IRs. l: "
        ++ show snames1 ++ ", r: " ++ show snames2  
  else
    throwError $
      "Name mismatch while comparing IRs: "
      ++ irName ir1 ++ " /= " ++ irName ir2  
  where 
    lookupSort :: MonadError Err m => String -> IR -> m Sort
    lookupSort n ir = 
      case L.find (\s -> name s == n) (sorts ir) of 
        (Just s) -> return s
        Nothing  -> throwError $
          "Sort lookup failed for key: " ++ n 
-} 
