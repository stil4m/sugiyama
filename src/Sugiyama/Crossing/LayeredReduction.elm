module Sugiyama.Crossing.LayeredReduction exposing (..)

import List.Extra as List
import List
import Sugiyama.Domain exposing (..)
import Sugiyama.Cache as C exposing (Cache)
import Sugiyama.Utils exposing (orderedPairs)
import Sugiyama.Crossing.Computation as Computation
import Dict exposing (Dict)


optimizeCrossing : ( LayeredGraph a, Cache a ) -> ( LayeredGraph a, Cache a )
optimizeCrossing ( input, cache ) =
    optimizeCrossing_ cache input


optimizeCrossing_ : Cache a -> LayeredGraph a -> ( LayeredGraph a, Cache a )
optimizeCrossing_ cache input =
    let
        ( before, cache1 ) =
            Computation.crossingsForLayeredGraph ( input, cache )

        ( optimized, cache2 ) =
            findBestLayers cache1 input

        ( after, cache3 ) =
            Computation.crossingsForLayeredGraph ( optimized, cache2 )
    in
        if after == 0 then
            ( optimized, cache3 )
        else if after < before then
            optimizeCrossing_ cache3 optimized
        else
            ( input, cache3 )


findBestLayers : Cache a -> LayeredGraph a -> ( LayeredGraph a, Cache a )
findBestLayers cache input =
    let
        _ =
            Debug.log "Find best layers" "!"

        edges =
            input.edges

        invertedEdges =
            edges
                |> List.map (\( x, y ) -> ( y, x ))

        layers =
            input.layers
                |> List.indexedMap (,)

        ( resultLayersToLeft, newCache ) =
            List.foldl (handleLayer edges) ( [], cache ) layers

        ( resultLayersToRight, newCache_ ) =
            List.foldr (handleLayer invertedEdges) ( [], newCache ) resultLayersToLeft

        newLayers =
            resultLayersToRight |> List.map Tuple.second |> List.reverse
    in
        ( { input | layers = newLayers }, newCache_ )


handleLayer : List ( Node, Node ) -> ( Int, Layer ) -> ( List ( Int, Layer ), Cache a ) -> ( List ( Int, Layer ), Cache a )
handleLayer edges ( layerId, next ) ( result, cache ) =
    case List.last result of
        Nothing ->
            ( [ ( layerId, next ) ], cache )

        Just ( lId, last ) ->
            case (C.loadFromCache last next cache) of
                Just hit ->
                    ( result ++ [ ( layerId, hit ) ]
                    , cache
                    )

                Nothing ->
                    let
                        ( computedLayer, cache_ ) =
                            reduceTo cache ( last, ( layerId, next ), edges )

                        newCache =
                            C.addToCache last next computedLayer cache_
                    in
                        ( result ++ [ ( layerId, computedLayer ) ]
                        , newCache
                        )


reduceTo : Cache a -> ( Layer, ( Int, Layer ), List ( Node, Node ) ) -> ( Layer, Cache a )
reduceTo cache ( aNodes, ( layerId, bNodes ), edges ) =
    if Computation.computeCrossings aNodes bNodes edges == 0 then
        ( bNodes, cache )
    else
        cache
            |> C.cachedPermutations
            |> Dict.get layerId
            |> Maybe.map (\permutation -> findOptimalPermutation cache permutation aNodes bNodes edges)
            |> Maybe.withDefault ( bNodes, cache )


findOptimalPermutation : Cache a -> LayerPermutation -> Layer -> Layer -> List ( Node, Node ) -> ( Layer, Cache a )
findOptimalPermutation cache permutations aNodes bNodes edges =
    let
        bNodePairCrossings =
            Computation.computeCrossingsPairs aNodes bNodes edges

        crossingsForPairs a =
            a
                |> List.filterMap (flip Dict.get bNodePairCrossings)
                |> List.sum
    in
        permutations
            |> List.map (\x -> ( x |> orderedPairs |> crossingsForPairs, x ))
            |> List.sortBy Tuple.first
            |> List.head
            |> Maybe.map (Tuple.second >> flip (,) cache)
            |> Maybe.withDefault ( bNodes, cache )
