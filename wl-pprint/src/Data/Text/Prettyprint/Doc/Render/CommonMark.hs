{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Render 'SimpleDoc' as common markdown AKA CommonMark in 'Text' format.
module Data.Text.Prettyprint.Doc.Render.CommonMark (
    Markdown,
    italics,
    bold,

    -- * Conversion to CommonMark-infused 'Text'
    renderLazy,
    renderStrict,

    -- * Render to a 'Handle'
    renderIO,

    -- ** Convenience functions
    putDoc, hPutDoc,
) where



import           Data.Text              (Text)
import qualified Data.Text              as T
import qualified Data.Text.Lazy         as TL
import qualified Data.Text.Lazy.Builder as TLB
import qualified Data.Text.Lazy.IO      as TL
import           System.IO

import Data.Text.Prettyprint.Doc
import Data.Text.Prettyprint.Doc.Render.Util.StackMachine

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif


-- $setup
--
-- (Definitions for the doctests)
--
-- >>> :set -XOverloadedStrings
-- >>> import qualified Data.Text.IO as T
-- >>> import qualified Data.Text.Lazy.IO as TL



-- | Styles supported by markdown documents
data Markdown = Bold | Italics
    deriving (Eq, Ord, Show)

-- | Render a document bold by enclosing it in @**@.
bold :: Doc Markdown -> Doc Markdown
bold = annotate Bold

-- | Render a document in italics by enclosing it in @*@.
italics :: Doc Markdown -> Doc Markdown
italics = annotate Italics



-- | Add Markdown-style markers for emphasis and strong emphasis.
--
-- >>> let doc = "This text" <+> italics ("is emphasized" <+> bold "even stronger" <> "!")
-- >>> let pprint = TL.putStrLn . renderLazy . layoutPretty defaultLayoutOptions
-- >>> pprint doc
-- This text *is emphasized **even stronger**!*
renderLazy :: SimpleDoc Markdown -> TL.Text
renderLazy doc
  = let (resultBuilder, remainingMarkdowns) = execStackMachine [] (build doc)
    in if null remainingMarkdowns
        then TLB.toLazyText resultBuilder
        else error ("There are "
                    <> show (length remainingMarkdowns)
                    <> " unpaired styles! Please report this as a bug.")

build :: SimpleDoc Markdown -> StackMachine TLB.Builder Markdown ()
build = \case
    SFail -> error "@SFail@ can not appear uncaught in a rendered @SimpleDoc@"
    SEmpty -> pure ()
    SChar c x -> do
        writeOutput (TLB.singleton c)
        build x
    SText _l t x -> do
        writeOutput (TLB.fromText t)
        build x
    SLine i x -> do
        writeOutput (TLB.singleton '\n' )
        writeOutput (TLB.fromText (T.replicate i " "))
        build x
    SAnnPush s x -> do
        pushStyle s
        writeOutput (styleToMarker s)
        build x
    SAnnPop x -> do
        s <- unsafePopStyle
        writeOutput (styleToMarker s)
        build x

styleToMarker :: Markdown -> TLB.Builder
styleToMarker = \case
    Italics -> TLB.fromString "*"
    Bold    -> TLB.fromString "**"

-- | Strict version of 'renderLazy'.
renderStrict :: SimpleDoc Markdown -> Text
renderStrict = TL.toStrict . renderLazy



-- | @('renderIO' h sdoc)@ writes @sdoc@ to the file @h@.
--
-- >>> renderIO System.IO.stdout (layoutPretty defaultLayoutOptions "hello\nworld")
-- hello
-- world
renderIO :: Handle -> SimpleDoc Markdown -> IO ()
renderIO h sdoc = TL.hPutStrLn h (renderLazy sdoc)

-- | @('putDoc' doc)@ prettyprints document @doc@ to standard output, with a
-- page width of 80 characters and a ribbon width of 32 characters.
--
-- >>> putDoc ("hello" <+> "world")
-- hello world
--
-- @
-- 'putDoc' = 'hPutDoc' 'stdout'
-- @
putDoc :: Doc Markdown -> IO ()
putDoc = hPutDoc stdout

-- | Like 'putDoc', but instead of using 'stdout', print to a user-provided
-- handle, e.g. a file or a socket. Uses a line length of 80, and a ribbon width
-- of 32 characters.
--
-- > main = withFile "someFile.txt" (\h -> hPutDoc h (vcat ["vertical", "text"]))
--
-- @
-- 'hPutDoc' h doc = 'renderIO' h ('layoutPretty' 'defaultLayoutOptions' doc)
-- @
hPutDoc :: Handle -> Doc Markdown -> IO ()
hPutDoc h doc = renderIO h (layoutPretty defaultLayoutOptions doc)
