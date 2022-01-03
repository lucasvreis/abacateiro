-- |

module PandocTransforms.Roam where
import PandocTransforms.Utilities hiding (Writer)
import Models
import PandocTransforms.Org
import PandocTransforms.LaTeX
import PandocTransforms.Emojis
import PandocTransforms.Links
import Control.Monad.Trans.Writer.Strict
import Data.UUID.Types as UUID (UUID, fromText)
import System.FilePath
import UnliftIO.Directory
import Caching
import Text.Pandoc.Citeproc
import qualified Data.Text as T
import UnliftIO
import Control.Monad.Logger
import Data.Time (Day(ModifiedJulianDay))

processRoam
  :: forall m. (MonadLogger m)
  => Pandoc -> CacheT Model m ()
processRoam (Pandoc meta blocks) = do
  foldMapM processDiv $ makeSections False Nothing blocks
  case lookupMeta "id" meta of
    Just (MetaString uuid) ->
      uuidOrUnit (addToModel blocks) $ Just uuid
    _ -> pure ()

  where
    uuidOrUnit f uuid = maybe (pure ()) f $ UUID.fromText =<< uuid

    addToModel blks uuid = do
      let (blks', bklinks) = runWriter $ processLinks blks
          result = do
            tit <- writeHtml $ Pandoc meta [Plain (docTitle meta)]
            bod <- writeHtml $ Pandoc meta blks'
            pure (tit, bod)
      case runPure result of
        Left e -> logErrorNS "Roam" ("Pandoc writer failed with:\n" <> renderError e)
        Right (tit, bod) -> do
          let bklinks' = map (\ ~(ruuid, excrpt) -> (ruuid, [RoamBacklink uuid tit excrpt])) bklinks
          tell $ insertRP uuid (BlogPost tit bod $ ModifiedJulianDay 1)
          tell $ addToRD uuid bklinks'

    processDiv :: Block -> CacheT Model m ()
    processDiv (Div (_, "section":_, kvs) blks)
      | any ((== "id") . fst) kvs =
          viaNonEmpty head (map snd $ filter ((== "id") . fst) kvs)
          & uuidOrUnit (addToModel blks)
    processDiv _ = pure ()

    processLinks :: [Block] -> Writer [(UUID, Text)] [Block]
    processLinks =
      mapM (mapWriter mapper . (walkM processLink))
      where
        mapper :: (Block, [UUID]) -> (Block, [(UUID, Text)])
        mapper ~(b, xs) =
          let excerpt = fromRight "" $ runPure $ writeHtml $ Pandoc meta [b]
          in (b, map (, excerpt) xs)

    processLink :: Inline -> Writer [UUID] Inline
    processLink (Link attr alt (url, titl)) =
      let same = pure $ Link attr alt (url, titl)
      in case T.breakOn ":" url of
        ("id", uid) -> case UUID.fromText $ T.tail uid of
          Just uuid -> do
            tell [uuid]
            return $ Link attr alt ("/zettelkasten/" <> T.tail uid, titl)
          Nothing -> same
        _ -> same
    processLink x = pure x

convertRoam
  :: (MonadUnliftIO m, MonadLogger m)
  => FilePath
  -> Text
  -> CacheT Model m ()
convertRoam fp txt = do
  let dir = takeDirectory fp

  originalDir <- getCurrentDirectory

  tree <- liftIO $ do
    addToFileTree mempty "data/citstyle.csl"
    <* setCurrentDirectory dir
    >>= flip addToFileTree "."

  let doc = runPure $ do
        modifyPureState $ \ps -> ps { stFiles = tree }
        parsed <- readOrg readerOptions txt
                  <&> applyTransforms
                  <&> setOrgVars
                  <&> walk (fixLinks dir) -- Maybe we should move this out of this function and instead take a list of transforms
                  >>= preambilizeKaTeX
        if isJust . lookupMeta "bibliography" . getMeta $ parsed
        then processCitations parsed
        else pure parsed
  case doc of
    Left e -> logErrorNS "Pandoc conversion" (renderError e)
    Right p -> processRoam =<< renderLaTeX p

  setCurrentDirectory originalDir

  where
    applyTransforms p = foldr ($) p transforms

    transforms :: [Pandoc -> Pandoc]
    transforms =
      [ walk convertEmojis
      , headerShift 1
      , setMetaP "lang" "pt-BR"
      , setMetaP "csl" "data/citstyle.csl"
      ]
