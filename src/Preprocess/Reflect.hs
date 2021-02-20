module Preprocess.Reflect
  ( reflectCode,
    reflectEnumItem,
    reflectEnumCase,
    reflectMetaType,
  )
where

import Data.EnumCase
import Data.Env
import Data.Hint
import Data.Ident
import Data.Maybe (fromMaybe)
import Data.MetaTerm
import Data.Namespace
import qualified Data.Text as T
import Data.Tree
import Text.Read (readMaybe)

-- reflect :: MetaTermPlus -> WithEnv MetaTermPlus
-- reflect tree =
--   reflect' 1 tree

-- reflect' :: Int -> MetaTermPlus -> WithEnv MetaTermPlus
-- reflect' level tree =
--   case tree of
--     (m, MetaTermLeaf atom)
--       | level > 1 ->
--         return (m, MetaTermLeaf atom)
--       | Just i <- readMaybe $ T.unpack atom ->
--         return (m, MetaTermInt64 i)
--       | otherwise ->
--         return (m, MetaTermVar $ asIdent atom)
--     (m, MetaTermNode treeList)
--       | level > 1 -> do
--         case treeList of
--           (_, MetaTermLeaf headAtom) : rest -> do
--             case headAtom of
--               "leaf"
--                 | [(_, MetaTermLeaf atom)] <- rest -> do
--                   return (m, MetaTermLeaf atom)
--                 | otherwise ->
--                   raiseSyntaxError m "(leaf LEAF)"
--               "node" -> do
--                 rest' <- mapM (reflect' level) rest
--                 return (m, MetaTermNode rest')
--               "quote"
--                 | [e] <- rest -> do
--                   e' <- reflect' (level + 1) e
--                   return (m, MetaTermNecIntro e')
--                 | otherwise ->
--                   raiseSyntaxError m "(quote TREE)"
--               "unquote"
--                 | [e] <- rest -> do
--                   e' <- reflect' (level - 1) e
--                   return (m, MetaTermNecElim e')
--                 | otherwise ->
--                   raiseSyntaxError m "(unquote TREE)"
--               _ -> do
--                 treeList' <- mapM (reflect' level) treeList
--                 return (m, MetaTermNode treeList')
--           _ -> do
--             treeList' <- mapM (reflect' level) treeList
--             return (m, MetaTermNode treeList')
--       | otherwise ->
--         case treeList of
--           [] ->
--             raiseSyntaxError m "(TREE TREE*)"
--           leaf@(_, MetaTermLeaf headAtom) : rest -> do
--             case headAtom of
--               "lambda"
--                 | [(_, MetaTermNode xs), e] <- rest -> do
--                   xs' <- mapM reflectIdent xs
--                   e' <- reflect' level e
--                   return (m, MetaTermImpIntro xs' Nothing e')
--                 | otherwise ->
--                   raiseSyntaxError m "(lambda (LEAF*) TREE)"
--               "lambda+"
--                 | [(_, MetaTermNode args@(_ : _)), e] <- rest -> do
--                   xs' <- mapM reflectIdent (init args)
--                   rest' <- reflectIdent $ last args
--                   e' <- reflect' level e
--                   return (m, MetaTermImpIntro xs' (Just rest') e')
--                 | otherwise ->
--                   raiseSyntaxError m "(lambda+ (LEAF LEAF*) TREE)"
--               "apply"
--                 | e : es <- rest -> do
--                   e' <- reflect' level e
--                   es' <- mapM (reflect' level) es
--                   return (m, MetaTermImpElim e' es')
--                 | otherwise ->
--                   raiseSyntaxError m "(apply TREE TREE*)"
--               "fix"
--                 | [(_, MetaTermLeaf f), (_, MetaTermNode xs), e] <- rest -> do
--                   xs' <- mapM reflectIdent xs
--                   e' <- reflect e
--                   return (m, MetaTermFix (asIdent f) xs' Nothing e')
--                 | otherwise ->
--                   raiseSyntaxError m "(fix LEAF (LEAF*) TREE)"
--               "fix+"
--                 | [(_, MetaTermLeaf f), (_, MetaTermNode args@(_ : _)), e] <- rest -> do
--                   xs' <- mapM reflectIdent (init args)
--                   rest' <- reflectIdent $ last args
--                   e' <- reflect e
--                   return (m, MetaTermFix (asIdent f) xs' (Just rest') e')
--                 | otherwise ->
--                   raiseSyntaxError m "(fix+ LEAF (LEAF LEAF*) TREE)"
--               "quote"
--                 | [e] <- rest -> do
--                   e' <- reflect' (level + 1) e
--                   return (m, MetaTermNecIntro e')
--                 | otherwise ->
--                   raiseSyntaxError m "(quote TREE)"
--               "unquote"
--                 | [e] <- rest -> do
--                   if level - 1 < 1
--                     then do
--                       p' e
--                       raiseError m "cannot unquote a term at the base calculus"
--                     else do
--                       e' <- reflect' (level - 1) e
--                       return (m, MetaTermNecElim e')
--                 | otherwise ->
--                   raiseSyntaxError m "(unquote TREE)"
--               "switch"
--                 | e : cs <- rest -> do
--                   e' <- reflect' level e
--                   cs' <- mapM reflectEnumClause cs
--                   i <- newNameWith' "switch"
--                   return (m, MetaTermEnumElim (e', i) cs')
--                 | otherwise ->
--                   raiseSyntaxError m "(switch TREE TREE*)"
--               "thunk"
--                 | [e] <- rest -> do
--                   e' <- reflect' level e
--                   return (m, MetaTermImpIntro [] Nothing e')
--                 | otherwise ->
--                   raiseSyntaxError m "(thunk TREE)"
--               _ ->
--                 reflectAux m leaf rest
--           leaf : rest ->
--             reflectAux m leaf rest
--     -- reflectされたコードのunquoteの中にはこれらが出てくる
--     (_, MetaTermVar _) ->
--       return tree
--     (m, MetaTermImpIntro xs mRest e) -> do
--       e' <- reflect' level e
--       return (m, MetaTermImpIntro xs mRest e')
--     (m, MetaTermImpElim e es) -> do
--       e' <- reflect' level e
--       es' <- mapM (reflect' level) es
--       return (m, MetaTermImpElim e' es')
--     (m, MetaTermFix f xs mRest e) -> do
--       e' <- reflect' level e
--       return (m, MetaTermFix f xs mRest e')
--     (m, MetaTermNecIntro e) -> do
--       e' <- reflect' (level + 1) e
--       return (m, MetaTermNecIntro e')
--     (m, MetaTermNecElim e) -> do
--       e' <- reflect' (level - 1) e
--       return (m, MetaTermNecElim e')
--     (_, MetaTermConst _) ->
--       return tree
--     (_, MetaTermInt64 _) ->
--       return tree
--     (_, MetaTermEnumIntro _) ->
--       return tree
--     (m, MetaTermEnumElim (e, i) caseList) -> do
--       let (cs, es) = unzip caseList
--       e' <- reflect' level e
--       es' <- mapM (reflect' level) es
--       return (m, MetaTermEnumElim (e', i) (zip cs es'))

-- (m, _) -> do
--   p' tree
--   raiseCritical m "Preprocess.Reflect.reflect called for a non-AST term (compiler bug)"

reflectCode :: TreePlus -> WithEnv MetaTermPlus
reflectCode tree =
  case tree of
    (m, TreeLeaf atom)
      | Just i <- readMaybe $ T.unpack atom ->
        return (m, MetaTermInt64 i)
      | otherwise ->
        return (m, MetaTermVar $ asIdent atom)
    (m, TreeNode treeList) ->
      case treeList of
        [] ->
          raiseSyntaxError m "(TREE TREE*)"
        leaf@(_, TreeLeaf headAtom) : rest -> do
          case headAtom of
            "lambda"
              | [(_, TreeNode xs), e] <- rest -> do
                xs' <- mapM reflectIdent xs
                e' <- reflectCode e
                return (m, MetaTermImpIntro xs' Nothing e')
              | otherwise ->
                raiseSyntaxError m "(lambda (LEAF*) TREE)"
            "lambda+"
              | [(_, TreeNode args@(_ : _)), e] <- rest -> do
                xs' <- mapM reflectIdent (init args)
                rest' <- reflectIdent $ last args
                e' <- reflectCode e
                return (m, MetaTermImpIntro xs' (Just rest') e')
              | otherwise ->
                raiseSyntaxError m "(lambda+ (LEAF LEAF*) TREE)"
            "apply"
              | e : es <- rest -> do
                e' <- reflectCode e
                es' <- mapM (reflectCode) es
                return (m, MetaTermImpElim e' es')
              | otherwise ->
                raiseSyntaxError m "(apply TREE TREE*)"
            "fix"
              | [(_, TreeLeaf f), (_, TreeNode xs), e] <- rest -> do
                xs' <- mapM reflectIdent xs
                e' <- reflectCode e
                return (m, MetaTermFix (asIdent f) xs' Nothing e')
              | otherwise ->
                raiseSyntaxError m "(fix LEAF (LEAF*) TREE)"
            "fix+"
              | [(_, TreeLeaf f), (_, TreeNode args@(_ : _)), e] <- rest -> do
                xs' <- mapM reflectIdent (init args)
                rest' <- reflectIdent $ last args
                e' <- reflectCode e
                return (m, MetaTermFix (asIdent f) xs' (Just rest') e')
              | otherwise ->
                raiseSyntaxError m "(fix+ LEAF (LEAF LEAF*) TREE)"
            "quote"
              | [e] <- rest -> do
                e' <- reflectCode e
                return (m, MetaTermNecIntro e')
              | otherwise ->
                raiseSyntaxError m "(quote TREE)"
            "unquote"
              | [e] <- rest -> do
                e' <- reflectCode e
                return (m, MetaTermNecElim e')
              | otherwise ->
                raiseSyntaxError m "(unquote TREE)"
            "switch"
              | e : cs <- rest -> do
                e' <- reflectCode e
                cs' <- mapM reflectEnumClause cs
                i <- newNameWith' "switch"
                return (m, MetaTermEnumElim (e', i) cs')
              | otherwise ->
                raiseSyntaxError m "(switch TREE TREE*)"
            "quasiquote"
              | [e] <- rest ->
                reflectData e
              | otherwise ->
                raiseSyntaxError m "(quasiquote TREE)"
            _ ->
              reflectAux m leaf rest
        leaf : rest ->
          reflectAux m leaf rest

-- reflectされたコードのunquoteの中にはこれらが出てくる
-- (_, MetaTermVar _) ->
--   return tree
-- (m, MetaTermImpIntro xs mRest e) -> do
--   e' <- reflectCode e
--   return (m, MetaTermImpIntro xs mRest e')
-- (m, MetaTermImpElim e es) -> do
--   e' <- reflectCode e
--   es' <- mapM (reflectCode) es
--   return (m, MetaTermImpElim e' es')
-- (m, MetaTermFix f xs mRest e) -> do
--   e' <- reflectCode e
--   return (m, MetaTermFix f xs mRest e')
-- (m, MetaTermNecIntro e) -> do
--   e' <- reflectCode e
--   return (m, MetaTermNecIntro e')
-- (m, MetaTermNecElim e) -> do
--   e' <- reflectCode e
--   return (m, MetaTermNecElim e')
-- (_, MetaTermConst _) ->
--   return tree
-- (_, MetaTermInt64 _) ->
--   return tree
-- (_, MetaTermEnumIntro _) ->
--   return tree
-- (m, MetaTermEnumElim (e, i) caseList) -> do
--   let (cs, es) = unzip caseList
--   e' <- reflectCode e
--   es' <- mapM (reflectCode) es
--   return (m, MetaTermEnumElim (e', i) (zip cs es'))

reflectData :: TreePlus -> WithEnv MetaTermPlus
reflectData tree = do
  case tree of
    (m, TreeLeaf atom) ->
      return (m, MetaTermLeaf atom)
    (m, TreeNode treeList) ->
      case treeList of
        (_, TreeLeaf "quasiunquote") : rest
          | [e] <- rest -> do
            reflectCode e
          | otherwise ->
            raiseSyntaxError m "(quasiunquote TREE)"
        _ -> do
          treeList' <- mapM reflectData treeList
          return (m, MetaTermNode treeList')

reflectAux :: Hint -> TreePlus -> [TreePlus] -> WithEnv MetaTermPlus
reflectAux m f args = do
  f' <- reflectCode f
  args' <- mapM reflectCode args
  return (m, MetaTermImpElim f' args')

-- modifyArgs :: MetaTermPlus -> [MetaTermPlus] -> WithEnv [MetaTermPlus]
-- modifyArgs f args = do
--   thunkEnv <- gets autoThunkEnv
--   quoteEnv <- gets autoQuoteEnv
--   case f of
--     (_, MetaTermVar name)
--       | S.member (asText name) thunkEnv ->
--         return $ map wrapWithThunk args
--       | S.member (asText name) quoteEnv ->
--         return $ map wrapWithQuote args
--     _ ->
--       return args

reflectIdent :: TreePlus -> WithEnv Ident
reflectIdent tree =
  case tree of
    (_, TreeLeaf x) ->
      return $ asIdent x
    t ->
      raiseSyntaxError (fst t) "LEAF"

-- wrapWithThunk :: MetaTermPlus -> MetaTermPlus
-- wrapWithThunk (m, t) =
--   (m, MetaTermNode [(m, MetaTermLeaf "thunk"), (m, t)])

-- wrapWithQuote :: MetaTermPlus -> MetaTermPlus
-- wrapWithQuote (m, t) =
--   (m, MetaTermNode [(m, MetaTermLeaf "quote"), (m, t)])

reflectEnumItem :: Hint -> T.Text -> [TreePlus] -> WithEnv [(T.Text, Int)]
reflectEnumItem m name ts = do
  xis <- reflectEnumItem' name $ reverse ts
  if isLinear (map snd xis)
    then return $ reverse xis
    else raiseError m "found a collision of discriminant"

reflectEnumItem' :: T.Text -> [TreePlus] -> WithEnv [(T.Text, Int)]
reflectEnumItem' name treeList =
  case treeList of
    [] ->
      return []
    [t] -> do
      (s, mj) <- reflectEnumItem'' t
      return [(name <> nsSep <> s, fromMaybe 0 mj)]
    (t : ts) -> do
      ts' <- reflectEnumItem' name ts
      (s, mj) <- reflectEnumItem'' t
      return $ (name <> nsSep <> s, fromMaybe (1 + headDiscriminantOf ts') mj) : ts'

reflectEnumItem'' :: TreePlus -> WithEnv (T.Text, Maybe Int)
reflectEnumItem'' tree =
  case tree of
    (_, TreeLeaf s) ->
      return (s, Nothing)
    (_, TreeNode [(_, TreeLeaf s), (_, TreeLeaf i)])
      | Just i' <- readMaybe $ T.unpack i ->
        return (s, Just i')
    t ->
      raiseSyntaxError (fst t) "LEAF | (LEAF LEAF)"

headDiscriminantOf :: [(T.Text, Int)] -> Int
headDiscriminantOf labelNumList =
  case labelNumList of
    [] ->
      0
    ((_, i) : _) ->
      i

reflectEnumClause :: TreePlus -> WithEnv (EnumCasePlus, MetaTermPlus)
reflectEnumClause tree =
  case tree of
    (_, TreeNode [c, e]) -> do
      c' <- reflectEnumCase c
      e' <- reflectCode e
      return (c', e')
    e ->
      raiseSyntaxError (fst e) "(TREE TREE)"

reflectEnumCase :: TreePlus -> WithEnv EnumCasePlus
reflectEnumCase tree =
  case tree of
    (m, TreeNode [(_, TreeLeaf "enum-introduction"), (_, TreeLeaf l)]) ->
      return (m, EnumCaseLabel l)
    (m, TreeLeaf "default") ->
      return (m, EnumCaseDefault)
    (m, TreeLeaf l) ->
      return (m, EnumCaseLabel l)
    (m, _) ->
      raiseSyntaxError m "default | LEAF"

reflectMetaType :: TreePlus -> WithEnv ([Ident], MetaTypePlus)
reflectMetaType tree =
  case tree of
    (m, TreeNode ((_, TreeLeaf "forall") : rest))
      | [(_, TreeNode args), cod] <- rest -> do
        xs <- mapM reflectIdent args
        cod' <- reflectMetaType' cod
        return (xs, cod')
      | otherwise ->
        raiseSyntaxError m "(forall (LEAF*) TREE)"
    _ -> do
      t <- reflectMetaType' tree
      return ([], t)

reflectMetaType' :: TreePlus -> WithEnv MetaTypePlus
reflectMetaType' tree = do
  -- eenv <- gets enumEnv
  case tree of
    (m, TreeLeaf x) -> do
      return (m, MetaTypeVar (asIdent x))
    -- (m, TreeNode []) ->
    --   raiseSyntaxError m "(TREE TREE*)"
    (m, TreeNode ((_, TreeLeaf headAtom) : ts))
      | "arrow" == headAtom ->
        case ts of
          [(_, TreeNode domList), cod] -> do
            domList' <- mapM reflectMetaType' domList
            cod' <- reflectMetaType' cod
            return (m, MetaTypeArrow domList' cod')
          _ ->
            raiseSyntaxError m "(arrow (TREE*) TREE)"
      | "box" == headAtom ->
        case ts of
          [t] -> do
            t' <- reflectMetaType' t
            return (m, MetaTypeNec t')
          _ ->
            raiseSyntaxError m "(box TREE)"
      | otherwise ->
        raiseSyntaxError m "(arrow (TREE*) TREE) | (meta TREE)"
    (m, _) ->
      raiseSyntaxError m "(LEAF TREE*)"

-- raiseCritical (fst tree) "reflectMetaType' called for a non-AST term (compiler-bug)"

--  Map.member x eenv ->
--  return (m, MetaTypeEnum x)
--  "i64" == x ->
--  return (m, MetaTypeInt64)
--  "code" == x ->
--  return (m, MetaTypeAST)

-- (arrow ((box AST) (box AST)) (box AST))
-- Q := box code みたいにしてもいいかも？
-- syntax, expressionなどいろいろある。sexpとか？S式だし「S」でいいかも？
-- Q := Quote S
-- (arrow ((quote S) (quote S)) (quote S))
-- (arrow ('S 'S) 'S) とかでもいいかな？型とtermのほうで同じ構文をつかうやつ。
-- (arrow ('code 'code) 'code)みたいな？
-- (hom 'code 'code)とかって書けると, まあ, けっこう嬉しい気がする。
-- でも,やっぱちょっとわかりづらいか。ひとつの記号はひとつの意味で。
-- (meta code)とかだろうか。quote foo : (meta code)みたいになる。
-- eval : forall a. meta code -> aとか。
-- K : meta (a -> b) -> meta a -> meta bとか。まあ, "meta" かな。
-- しかし, メタ言語からみれば, box Aはむしろ対象言語のコードなんだよな。metaとは逆だ。未来の世界。
-- boxかなあ。quoteであり。(next code)とか？
