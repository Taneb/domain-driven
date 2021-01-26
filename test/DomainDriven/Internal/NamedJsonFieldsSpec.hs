{-# LANGUAGE DerivingVia #-}
module DomainDriven.Internal.NamedJsonFieldsSpec where

import           Prelude
import           GHC.Generics
import           Data.Aeson
import           Data.Text                      ( Text )
import           DomainDriven.Internal.NamedJsonFields
import           DomainDriven.Internal.JsonFieldName
import           Test.QuickCheck
import           Test.QuickCheck.Arbitrary.ADT
import           Test.QuickCheck.Classes
import           Data.Proxy
import           Control.Monad
import           Test.Hspec
import           Data.String
import           Test.Hspec.QuickCheck
import           Data.OpenApi

data Test1 = Test1
    { namedField1 :: Int
    , namedField2 :: Double
    }
    deriving (Show, Eq, Ord, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (NamedJsonFields Test1)

instance Arbitrary Test1 where
    arbitrary = genericArbitrary

newtype MyText = MyText Text
    deriving (Show, Eq, Ord, Generic)
    deriving newtype (FromJSON, ToJSON, IsString, ToSchema)
    deriving anyclass (JsonFieldName)

------------------------------------------------------------------------------


instance Arbitrary Duplicated where
    arbitrary = genericArbitrary

instance Arbitrary MyText where
    arbitrary = elements ["hej", "hopp", "kalle", "anka", "ekorre"]

data Test2
    = Test2a
    | Test2b Int MyText
    | Test2c MyText
    | Test2d String String
    | Test2e String
    deriving (Show, Eq, Ord, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (NamedJsonFields Test2)

instance Arbitrary Test2 where
    arbitrary = genericArbitrary

data Duplicated
    = Duplicated1 Int Int Int String Int String
    | Duplicated2 Int String Int Double
    deriving (Show, Eq, Generic)
    --deriving anyclass (FromJSON, ToJSON, ToSchema)
    deriving (FromJSON, ToJSON, ToSchema) via (NamedJsonFields Duplicated)

spec :: Spec
spec = do
    describe "ToJSON and FromJSON instances" $ do
        void $ traverse (uncurry prop) (lawsProperties $ jsonLaws $ Proxy @Test1)
        void $ traverse (uncurry prop) (lawsProperties $ jsonLaws $ Proxy @Test2)
        void $ traverse (uncurry prop) (lawsProperties $ jsonLaws $ Proxy @Duplicated)
    describe "ToSchema instances" $ do
        prop "Test1" $ \(a :: Test1) -> validateToJSON a == []
        prop "Test2" $ \(a :: Test2) -> validateToJSON a == []
        prop "Duplicated" $ \(a :: Duplicated) -> validateToJSON a == []