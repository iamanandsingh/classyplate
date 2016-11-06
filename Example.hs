{-# LANGUAGE Rank2Types, ConstraintKinds, KindSignatures, TypeFamilies, ScopedTypeVariables, MultiParamTypeClasses, AllowAmbiguousTypes
           , FlexibleContexts, FlexibleInstances, UndecidableInstances, DataKinds, TypeApplications, DeriveGeneric, DeriveDataTypeable
           , TypeOperators, PolyKinds #-}
module Example where

import GHC.Exts
import Data.Maybe
import GHC.Generics (Generic)
import qualified GHC.Generics as GG
import Data.Data (Data)
import Control.Parallel.Strategies

import Data.Type.Bool
import Data.Type.List hiding (Distinct)

type family ClassIgnoresSubtree (cls :: * -> Constraint) (typ :: *) :: Bool where
  ClassIgnoresSubtree cls typ = Distinct (SelectedElements cls) (MemberTypes typ)

type family Distinct (ls1 :: [k]) (ls2 :: [k]) :: Bool where
  Distinct '[] ls2 = True
  Distinct ls1 '[] = True
  Distinct (e1 ': ls1) ls2 = Not (Find e1 ls2) && Distinct ls1 ls2

type family MemberTypes (typ :: *) :: [*] where
  MemberTypes t = GetMemberTypes '[] t

type family GetMemberTypes (checked :: [*]) (typ :: *) :: [*] where 
  -- primitive types without Rep instance
  GetMemberTypes checked Char = '[Char]
  GetMemberTypes checked t = GetElementTypes checked (GG.Rep t)

type family GetElementTypes (checked :: [*]) (typ :: * -> *) :: [*] where 
  GetElementTypes checked (GG.D1 md cons) = GetElementTypesCons checked cons

type family GetElementTypesCons (checked :: [*]) (typ :: * -> *) where 
  GetElementTypesCons checked (GG.C1 mc flds) = GetElementTypesFields checked flds
  GetElementTypesCons checked (c1 GG.:+: c2) = GetElementTypesCons checked c1 `Union` GetElementTypesCons checked c2

type family GetElementTypesFields (checked :: [*]) (typ :: * -> *) where 
  GetElementTypesFields checked (fld1 GG.:*: fld2) = GetElementTypesFields checked fld1 `Union` GetElementTypesFields checked fld2
  GetElementTypesFields checked (GG.S1 ms (GG.Rec0 t)) = GetElementTypesField checked (Find t checked) t
  GetElementTypesFields checked (GG.U1) = '[]

type family GetElementTypesField (checked :: [*]) (inChecked :: Bool) (typ :: *) where 
  GetElementTypesField checked True typ = '[]
  GetElementTypesField checked False typ = Insert typ (GetMemberTypes (typ ': checked) typ)

type family SelectedElements (c :: * -> Constraint) :: [*]


-------------------------------- USAGE-SPECIFIC PART

test = apply @F trf $ ABC (BA (ABC B (CB B))) (CB B)

class F a where
  trf :: a -> a

instance F B where
  trf b = B

instance F C where
  trf c = CB B
  
type instance AppSelector F A = 'False
type instance AppSelector F B = 'True
type instance AppSelector F C = 'True
type instance AppSelector F D = 'False
type instance AppSelector F E = 'False

type instance SelectedElements F = '[ B, C ]

--------

test2 = applyM @Debug debugCs $ ABC (BA (ABC B (CB B))) (CD D)

class Debug a where
  debugCs :: a -> IO a

instance Debug C where
  debugCs c = print c >> return c
  
type instance AppSelector Debug a = DebugSelector a

type instance SelectedElements Debug = '[ C ]

type family DebugSelector t where
  DebugSelector C = 'True
  DebugSelector _ = 'False

--------

test3 = apply @(MonoMatch C) (monoApp (\c -> case c of CB b -> CB (BA (ABC b (CB B))); )) $ ABC (BA (ABC B (CB B))) (CB B)

type instance SelectedElements (MonoMatch t) = '[ t ]

-------

class DebugWhere a where
  debugWhereCs :: a -> IO a
  debugSubtree :: a -> Bool
  debugSubtree _ = True

instance DebugWhere C where
  debugWhereCs c = print c >> return c

instance DebugWhere D where
  debugWhereCs c = return c
  debugSubtree _ = False

instance DebugWhere E where
  debugWhereCs c = error "Should never go here" >> return c 

type instance AppSelector DebugWhere a = DebugWhereSelector a

type instance SelectedElements DebugWhere = '[ C, D, E ]

type family DebugWhereSelector t where
  DebugWhereSelector C = 'True
  DebugWhereSelector D = 'True
  DebugWhereSelector E = 'True
  DebugWhereSelector _ = 'False

test4 = applySelectiveM @DebugWhere debugWhereCs (return . debugSubtree) $ ABC (BA (ABC B (CB B))) (CD (DDE D E))


-------------------------------- REPRESENTATION-SPECIFIC PART

data A = ABC B C deriving (Show, Generic, Data)
data B = B | BA A deriving (Show, Generic, Data)
data C = CB B | CD D deriving (Show, Generic, Data)
data D = DDE D E | D deriving (Show, Generic, Data)
data E = E deriving (Show, Generic, Data)

instance NFData A
instance NFData B
instance NFData C
instance NFData D
instance NFData E

type GoodOperationFor c e = (App (AppSelector c e) c e, AutoApply c (ClassIgnoresSubtree c e) e)
-- type GoodOperationFor c e = (App (AppSelector c e) c e)

type GoodOperation c = (GoodOperationFor c A, GoodOperationFor c B, GoodOperationFor c C, GoodOperationFor c D, GoodOperationFor c E)

instance GoodOperation c => Apply c A where
  apply f (ABC b c) = app @(AppSelector c A) @c f $ ABC (apply @c f b) (apply @c f c)
  applyM f (ABC b c) = appM @(AppSelector c A) @c f =<< (ABC <$> applyM @c f b <*> applyM @c f c)
  applySelective f pred val@(ABC b c) = appIf @c f pred val (ABC (applySelective @c f pred b) (applySelective @c f pred c))
  applySelectiveM f pred val@(ABC b c) = appIfM @c f pred val (ABC <$> applySelectiveM @c f pred b <*> applySelectiveM @c f pred c)

instance GoodOperation c => AutoApply c False A where
  applyAuto f (ABC b c) = app @(AppSelector c A) @c f $ ABC (applyAuto @c @(ClassIgnoresSubtree c B) f b) (applyAuto @c @(ClassIgnoresSubtree c C) f c)
  applyAutoM f (ABC b c) = appM @(AppSelector c A) @c f =<< (ABC <$> applyAutoM @c @(ClassIgnoresSubtree c B) f b <*> applyAutoM @c @(ClassIgnoresSubtree c C) f c)

instance GoodOperation c => Apply c B where
  apply f B = app @(AppSelector c B) @c f B
  apply f (BA a) = app @(AppSelector c B) @c f $ BA (apply @c f a)

  applyM f B = appM @(AppSelector c B) @c f B
  applyM f (BA a) = appM @(AppSelector c B) @c f =<< (BA <$> applyM @c f a)

  applySelective f pred val@B = appIf @c f pred val B
  applySelective f pred val@(BA a) = appIf @c f pred val (BA (applySelective @c f pred a))

  applySelectiveM f pred val@B = appIfM @c f pred val (return B)
  applySelectiveM f pred val@(BA a) = appIfM @c f pred val (BA <$> applySelectiveM @c f pred a)

instance GoodOperation c => AutoApply c False B where
  applyAuto f B = app @(AppSelector c B) @c f B
  applyAuto f (BA a) = app @(AppSelector c B) @c f $ BA (applyAuto @c @(ClassIgnoresSubtree c A) f a)

  applyAutoM f B = appM @(AppSelector c B) @c f B
  applyAutoM f (BA a) = appM @(AppSelector c B) @c f =<< (BA <$> applyAutoM @c @(ClassIgnoresSubtree c A) f a)

instance GoodOperation c => Apply c C where
  apply f (CB b) = app @(AppSelector c C) @c f $ CB (apply @c f b)
  apply f (CD d) = app @(AppSelector c C) @c f $ CD (apply @c f d)

  applyM f (CB b) = appM @(AppSelector c C) @c f =<< (CB <$> applyM @c f b)
  applyM f (CD d) = appM @(AppSelector c C) @c f =<< (CD <$> applyM @c f d)

  applySelective f pred val@(CB b) = appIf @c f pred val (CB (applySelective @c f pred b))
  applySelective f pred val@(CD d) = appIf @c f pred val (CD (applySelective @c f pred d))

  applySelectiveM f pred val@(CB b) = appIfM @c f pred val (CB <$> applySelectiveM @c f pred b)
  applySelectiveM f pred val@(CD d) = appIfM @c f pred val (CD <$> applySelectiveM @c f pred d)

instance GoodOperation c => AutoApply c False C where
  applyAuto f (CB b) = app @(AppSelector c C) @c f $ CB (applyAuto @c @(ClassIgnoresSubtree c B) f b)
  applyAuto f (CD d) = app @(AppSelector c C) @c f $ CD (applyAuto @c @(ClassIgnoresSubtree c D) f d)

  applyAutoM f (CB b) = appM @(AppSelector c C) @c f =<< (CB <$> applyAutoM @c @(ClassIgnoresSubtree c B) f b)
  applyAutoM f (CD d) = appM @(AppSelector c C) @c f =<< (CD <$> applyAutoM @c @(ClassIgnoresSubtree c D) f d)

instance GoodOperation c => Apply c D where
  apply f (DDE d e) = app @(AppSelector c D) @c f $ DDE (apply @c f d) (apply @c f e)
  apply f D = app @(AppSelector c D) @c f $ D

  applyM f (DDE d e) = appM @(AppSelector c D) @c f =<< (DDE <$> applyM @c f d <*> applyM @c f e)
  applyM f D = appM @(AppSelector c D) @c f =<< (return D)

  applySelective f pred val@(DDE d e) = appIf @c f pred val (DDE (applySelective @c f pred d) (applySelective @c f pred e))
  applySelective f pred val@D = appIf @c f pred val D

  applySelectiveM f pred val@(DDE d e) = appIfM @c f pred val (DDE <$> applySelectiveM @c f pred d <*> applySelectiveM @c f pred e)
  applySelectiveM f pred val@D = appIfM @c f pred val (return D)

instance GoodOperation c => AutoApply c False D where
  applyAuto f (DDE d e) = app @(AppSelector c D) @c f $ DDE (applyAuto @c @(ClassIgnoresSubtree c D) f d) (applyAuto @c @(ClassIgnoresSubtree c E) f e)
  applyAuto f D = app @(AppSelector c D) @c f $ D

  applyAutoM f (DDE d e) = appM @(AppSelector c D) @c f =<< (DDE <$> applyAutoM @c @(ClassIgnoresSubtree c D) f d <*> applyAutoM @c @(ClassIgnoresSubtree c E) f e)
  applyAutoM f D = appM @(AppSelector c D) @c f =<< (return D)

instance GoodOperation c => Apply c E where
  apply f E = app @(AppSelector c E) @c f E
  applyM f E = appM @(AppSelector c E) @c f E
  applySelective f pred val@E = appIf @c f pred val E
  applySelectiveM f pred val@E = appIfM @c f pred val (return E)

instance GoodOperation c => AutoApply c False E where
  applyAuto f E = app @(AppSelector c E) @c f E
  applyAutoM f E = appM @(AppSelector c E) @c f E


--------------------------------- GENERIC PART


type family AppSelector (c :: * -> Constraint) (a :: *) :: Bool

class App (flag :: Bool) c b where
  app :: (forall a . c a => a -> a) -> b -> b
  appM :: Monad m => (forall a . c a => a -> m a) -> b -> m b
  appOpt :: (forall a . c a => a -> x) -> b -> Maybe x

instance c b => App 'True c b where
  {-# INLINE app #-}
  app f a = f a
  {-# INLINE appM #-}
  appM f a = f a
  {-# INLINE appOpt #-}
  appOpt f a = Just $ f a

instance App 'False c b where
  {-# INLINE app #-}
  app _ a = a
  {-# INLINE appM #-}
  appM _ a = return a
  {-# INLINE appOpt #-}
  appOpt _ _ = Nothing

class App (AppSelector c b) c b => Apply c b where
  apply :: (forall a . c a => a -> a) -> b -> b
  applyM :: Monad m => (forall a . c a => a -> m a) -> b -> m b

  applySelective :: (forall a . c a => a -> a) -> (forall a . c a => a -> Bool) -> b -> b
  applySelectiveM :: Monad m => (forall a . c a => a -> m a) -> (forall a . c a => a -> m Bool) -> b -> m b

class App (AppSelector c b) c b => AutoApply c (sel :: Bool) b where
  applyAuto :: (forall a . c a => a -> a) -> b -> b
  applyAutoM :: Monad m => (forall a . c a => a -> m a) -> b -> m b

applyAuto_ :: forall c b . AutoApply c (ClassIgnoresSubtree c b) b => (forall a . c a => a -> a) -> b -> b
{-# INLINE applyAuto_ #-}
applyAuto_ = applyAuto @c @(ClassIgnoresSubtree c b)

applyAutoM_ :: forall c b m . (AutoApply c (ClassIgnoresSubtree c b) b, Monad m) => (forall a . c a => a -> m a) -> b -> m b
{-# INLINE applyAutoM_ #-}
applyAutoM_ = applyAutoM @c @(ClassIgnoresSubtree c b)

instance App (AppSelector c b) c b => AutoApply c True b where
  applyAuto f a = app @(AppSelector c b) @c f a
  {-# INLINE applyAuto #-}
  applyAutoM f a = appM @(AppSelector c b) @c f a
  {-# INLINE applyAutoM #-}

{-# SPECIALIZE INLINE apply :: Apply (MonoMatch x) sel b => (forall a . MonoMatch x a => a -> a) -> b -> b #-}

class MonoMatch a b where
  monoApp :: (a -> a) -> b -> b

instance MonoMatch a a where
  monoApp = id
  {-# INLINE monoApp #-}

type instance AppSelector (MonoMatch a) b = TypEq a b

type family TypEq a b :: Bool where
  TypEq a a = 'True
  TypEq a b = 'False

appIf :: forall c b . App (AppSelector c b) c b => (forall a . c a => a -> a) -> (forall a . c a => a -> Bool) -> b -> b -> b
{-# INLINE appIf #-}
appIf f pred val combined = app @(AppSelector c b) @c f $ case appOpt @(AppSelector c b) @c pred val of
    Just False -> val
    _          -> combined

appIfM :: forall c b m . (App (AppSelector c b) c b, Monad m) => (forall a . c a => a -> m a) -> (forall a . c a => a -> m Bool) -> b -> m b -> m b
{-# INLINE appIfM #-}
appIfM f pred val combined = do
    doChildren <- fromMaybe (return True) $ appOpt @(AppSelector c b) @c pred val
    inner <- case doChildren of False -> return val
                                _     -> combined
    appM @(AppSelector c b) @c f inner
