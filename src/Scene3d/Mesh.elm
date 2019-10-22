module Scene3d.Mesh exposing
    ( Mesh
    , Points, LineSegments, Triangles
    , WithNormals, NoNormals, WithTangents, NoTangents, WithUV, NoUV, ShadowsEnabled, ShadowsDisabled
    , Option, cullBackFaces
    , empty
    , triangles, facets
    , indexed, smooth
    , lineSegments, polyline
    , points
    , enableShadows
    )

{-|

@docs Mesh

@docs Points, LineSegments, Triangles

@docs WithNormals, NoNormals, WithTangents, NoTangents, WithUV, NoUV, ShadowsEnabled, ShadowsDisabled


## Options

@docs Option, cullBackFaces


## Empty

@docs empty


## Triangles

@docs triangles, facets


## Indexed triangles

@docs indexed, smooth


## Lines

@docs lineSegments, polyline


## Points

@docs points


## Shadows

@docs withShadow

-}

import Array
import BoundingBox3d exposing (BoundingBox3d)
import Dict exposing (Dict)
import Geometry.Interop.LinearAlgebra.Point3d as Point3d
import Geometry.Interop.LinearAlgebra.Vector3d as Vector3d
import Length exposing (Meters)
import LineSegment3d exposing (LineSegment3d)
import Math.Vector3 exposing (Vec3)
import Point3d exposing (Point3d)
import Polyline3d exposing (Polyline3d)
import Quantity exposing (Quantity(..), Unitless)
import Scene3d.Types as Types exposing (Bounds, MeshData, PlainVertex, Shadow, ShadowEdge, SmoothVertex)
import Triangle3d exposing (Triangle3d)
import TriangularMesh exposing (TriangularMesh)
import Vector3d exposing (Vector3d)
import WebGL


type alias Mesh coordinates primitives =
    Types.Mesh coordinates primitives


type Points
    = Points


type LineSegments
    = LineSegments


type Triangles normals uv tangents shadows
    = Triangles normals uv tangents shadows


type WithNormals
    = WithNormals


type NoNormals
    = NoNormals


type WithUV
    = WithUV


type NoUV
    = NoUV


type WithTangents
    = WithTangents


type NoTangents
    = NoTangents


type ShadowsEnabled
    = ShadowsEnabled


type ShadowsDisabled
    = ShadowsDisabled


type Option
    = CullBackFaces


cullBackFaces : Option
cullBackFaces =
    CullBackFaces


plainVertex : Point3d Meters coordinates -> PlainVertex
plainVertex point =
    { position = Point3d.toVec3 point }


triangleAttributes : Triangle3d Meters coordinates -> ( PlainVertex, PlainVertex, PlainVertex )
triangleAttributes triangle =
    let
        ( p1, p2, p3 ) =
            Triangle3d.vertices triangle
    in
    ( plainVertex p1, plainVertex p2, plainVertex p3 )


facetAttributes : Triangle3d Meters coordinates -> ( SmoothVertex, SmoothVertex, SmoothVertex )
facetAttributes triangle =
    let
        ( p1, p2, p3 ) =
            Triangle3d.vertices triangle

        e1 =
            Vector3d.from p1 p2

        e2 =
            Vector3d.from p2 p3

        normal =
            Vector3d.toVec3 (e1 |> Vector3d.cross e2)
    in
    ( { position = Point3d.toVec3 p1, normal = normal }
    , { position = Point3d.toVec3 p2, normal = normal }
    , { position = Point3d.toVec3 p3, normal = normal }
    )


empty : Mesh coordinates primitives
empty =
    Types.EmptyMesh


withoutShadow : MeshData coordinates -> Mesh coordinates primitives
withoutShadow meshData =
    Types.Mesh meshData Nothing


isCullBackFaces : Option -> Bool
isCullBackFaces option =
    option == CullBackFaces


getCullBackFaces : List Option -> Bool
getCullBackFaces options =
    List.any isCullBackFaces options


triangles : List Option -> List (Triangle3d Meters coordinates) -> Mesh coordinates (Triangles NoNormals NoUV NoTangents ShadowsDisabled)
triangles options givenTriangles =
    case givenTriangles of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.hullOf Triangle3d.boundingBox first rest

                webGLMesh =
                    WebGL.triangles (List.map triangleAttributes givenTriangles)

                cullBack =
                    getCullBackFaces options
            in
            withoutShadow <|
                Types.Triangles bounds givenTriangles webGLMesh cullBack


facets : List Option -> List (Triangle3d Meters coordinates) -> Mesh coordinates (Triangles WithNormals NoUV NoTangents ShadowsDisabled)
facets options givenTriangles =
    case givenTriangles of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.hullOf Triangle3d.boundingBox first rest

                webGLMesh =
                    WebGL.triangles (List.map facetAttributes givenTriangles)

                cullBack =
                    getCullBackFaces options
            in
            withoutShadow <|
                Types.Facets bounds givenTriangles webGLMesh cullBack


collectPlain : Point3d Meters coordinates -> List PlainVertex -> List PlainVertex
collectPlain point accumulated =
    { position = Point3d.toVec3 point } :: accumulated


plainBoundsHelp : Float -> Float -> Float -> Float -> Float -> Float -> List PlainVertex -> BoundingBox3d Meters coordinates
plainBoundsHelp minX maxX minY maxY minZ maxZ remaining =
    case remaining of
        next :: rest ->
            let
                x =
                    Math.Vector3.getX next.position

                y =
                    Math.Vector3.getY next.position

                z =
                    Math.Vector3.getZ next.position
            in
            plainBoundsHelp
                (min minX x)
                (max maxX x)
                (min minY y)
                (max maxY y)
                (min minZ z)
                (max maxZ z)
                rest

        [] ->
            BoundingBox3d.fromExtrema
                { minX = Quantity minX
                , maxX = Quantity maxX
                , minY = Quantity minY
                , maxY = Quantity maxY
                , minZ = Quantity minZ
                , maxZ = Quantity maxZ
                }


plainBounds : PlainVertex -> List PlainVertex -> BoundingBox3d Meters coordinates
plainBounds first rest =
    let
        x =
            Math.Vector3.getX first.position

        y =
            Math.Vector3.getY first.position

        z =
            Math.Vector3.getZ first.position
    in
    plainBoundsHelp x x y y z z rest


indexed : List Option -> TriangularMesh (Point3d Meters coordinates) -> Mesh coordinates (Triangles NoNormals NoUV NoTangents ShadowsDisabled)
indexed options givenMesh =
    let
        collectedVertices =
            Array.foldr collectPlain [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    plainBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)

                cullBack =
                    getCullBackFaces options
            in
            withoutShadow <|
                Types.Indexed bounds givenMesh webGLMesh cullBack


collectSmooth : { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates } -> List SmoothVertex -> List SmoothVertex
collectSmooth { position, normal } accumulated =
    { position = Point3d.toVec3 position, normal = Vector3d.toVec3 normal }
        :: accumulated


smoothBoundsHelp : Float -> Float -> Float -> Float -> Float -> Float -> List SmoothVertex -> BoundingBox3d Meters coordinates
smoothBoundsHelp minX maxX minY maxY minZ maxZ remaining =
    case remaining of
        next :: rest ->
            let
                x =
                    Math.Vector3.getX next.position

                y =
                    Math.Vector3.getY next.position

                z =
                    Math.Vector3.getZ next.position
            in
            smoothBoundsHelp
                (min minX x)
                (max maxX x)
                (min minY y)
                (max maxY y)
                (min minZ z)
                (max maxZ z)
                rest

        [] ->
            BoundingBox3d.fromExtrema
                { minX = Quantity minX
                , maxX = Quantity maxX
                , minY = Quantity minY
                , maxY = Quantity maxY
                , minZ = Quantity minZ
                , maxZ = Quantity maxZ
                }


smoothBounds : SmoothVertex -> List SmoothVertex -> BoundingBox3d Meters coordinates
smoothBounds first rest =
    let
        x =
            Math.Vector3.getX first.position

        y =
            Math.Vector3.getY first.position

        z =
            Math.Vector3.getZ first.position
    in
    smoothBoundsHelp x x y y z z rest


smooth : List Option -> TriangularMesh { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates } -> Mesh coordinates (Triangles WithNormals NoUV NoTangents ShadowsDisabled)
smooth options givenMesh =
    let
        collectedVertices =
            Array.foldr collectSmooth [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    smoothBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)

                cullBack =
                    getCullBackFaces options
            in
            withoutShadow <|
                Types.Smooth bounds givenMesh webGLMesh cullBack


lineSegmentAttributes : LineSegment3d Meters coordinates -> ( PlainVertex, PlainVertex )
lineSegmentAttributes givenSegment =
    let
        ( p1, p2 ) =
            LineSegment3d.endpoints givenSegment
    in
    ( plainVertex p1, plainVertex p2 )


lineSegments : List Option -> List (LineSegment3d Meters coordinates) -> Mesh coordinates LineSegments
lineSegments options givenSegments =
    case givenSegments of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.hullOf LineSegment3d.boundingBox first rest

                webGLMesh =
                    WebGL.lines (List.map lineSegmentAttributes givenSegments)
            in
            withoutShadow <|
                Types.LineSegments bounds givenSegments webGLMesh


polyline : List Option -> Polyline3d Meters coordinates -> Mesh coordinates LineSegments
polyline options givenPolyline =
    let
        vertices =
            Polyline3d.vertices givenPolyline
    in
    case vertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    Point3d.hull first rest

                webGLMesh =
                    WebGL.lineStrip (List.map plainVertex vertices)
            in
            withoutShadow <|
                Types.Polyline bounds givenPolyline webGLMesh


points : List Option -> List (Point3d Meters coordinates) -> Mesh coordinates Points
points options givenPoints =
    case givenPoints of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    Point3d.hull first rest

                webGLMesh =
                    WebGL.points (List.map plainVertex givenPoints)
            in
            withoutShadow <|
                Types.Points bounds givenPoints webGLMesh


enableShadows : Mesh coordinates (Triangles normals uv tangents ShadowsDisabled) -> Mesh coordinates (Triangles normals uv tangents ShadowsEnabled)
enableShadows mesh =
    case mesh of
        Types.Mesh meshData Nothing ->
            Types.Mesh meshData (Just (createShadow meshData))

        Types.Mesh meshData (Just shadow) ->
            Types.Mesh meshData (Just shadow)

        Types.EmptyMesh ->
            Types.EmptyMesh


createShadow : MeshData coordinates -> Shadow coordinates
createShadow meshData =
    case meshData of
        Types.Triangles boundingBox meshTriangles _ _ ->
            let
                vertexTriples =
                    List.map Triangle3d.vertices meshTriangles
            in
            shadowImpl boundingBox (TriangularMesh.triangles vertexTriples)

        Types.Facets boundingBox meshTriangles _ _ ->
            let
                vertexTriples =
                    List.map Triangle3d.vertices meshTriangles
            in
            shadowImpl boundingBox (TriangularMesh.triangles vertexTriples)

        Types.Indexed boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox triangularMesh

        Types.Smooth boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox
                (TriangularMesh.mapVertices .position triangularMesh)

        Types.LineSegments _ _ _ ->
            Types.EmptyShadow

        Types.Polyline _ _ _ ->
            Types.EmptyShadow

        Types.Points _ _ _ ->
            Types.EmptyShadow


shadowImpl : BoundingBox3d Meters coordinates -> TriangularMesh (Point3d Meters coordinates) -> Shadow coordinates
shadowImpl boundingBox triangularMesh =
    let
        numVertices =
            Array.length (TriangularMesh.vertices triangularMesh)

        faceIndices =
            TriangularMesh.faceIndices triangularMesh

        faceVertices =
            TriangularMesh.faceVertices triangularMesh

        shadowEdges =
            buildShadowEdges numVertices faceIndices faceVertices Dict.empty

        shadowVolumeFaces =
            List.foldl collectShadowFaces [] shadowEdges
    in
    Types.Shadow shadowEdges (WebGL.triangles shadowVolumeFaces)


buildShadowEdges : Int -> List ( Int, Int, Int ) -> List ( Point3d Meters coordinates, Point3d Meters coordinates, Point3d Meters coordinates ) -> Dict Int (ShadowEdge coordinates) -> List (ShadowEdge coordinates)
buildShadowEdges numVertices faceIndices faceVertices edgeDictionary =
    case faceIndices of
        ( i, j, k ) :: remainingFaceIndices ->
            case faceVertices of
                ( p1, p2, p3 ) :: remainingFaceVertices ->
                    let
                        normal =
                            Vector3d.from p1 p2
                                |> Vector3d.cross (Vector3d.from p1 p3)
                                |> Vector3d.normalize

                        updatedEdgeDictionary =
                            if normal == Vector3d.zero then
                                -- Skip degenerate faces
                                edgeDictionary

                            else
                                edgeDictionary
                                    |> Dict.update (edgeKey numVertices i j)
                                        (updateShadowEdge i j p1 p2 normal)
                                    |> Dict.update (edgeKey numVertices j k)
                                        (updateShadowEdge j k p2 p3 normal)
                                    |> Dict.update (edgeKey numVertices k i)
                                        (updateShadowEdge k i p3 p1 normal)
                    in
                    buildShadowEdges numVertices
                        remainingFaceIndices
                        remainingFaceVertices
                        updatedEdgeDictionary

                [] ->
                    -- Should never happen, faceIndices and faceVertices should
                    -- always be the same length
                    []

        [] ->
            Dict.values edgeDictionary


collectShadowFaces : ShadowEdge coordinates -> List ( SmoothVertex, SmoothVertex, SmoothVertex ) -> List ( SmoothVertex, SmoothVertex, SmoothVertex )
collectShadowFaces { startPoint, endPoint, leftNormal, rightNormal } accumulated =
    let
        firstFace =
            ( { position = Point3d.toVec3 startPoint, normal = Vector3d.toVec3 rightNormal }
            , { position = Point3d.toVec3 endPoint, normal = Vector3d.toVec3 rightNormal }
            , { position = Point3d.toVec3 endPoint, normal = Vector3d.toVec3 leftNormal }
            )

        secondFace =
            ( { position = Point3d.toVec3 endPoint, normal = Vector3d.toVec3 leftNormal }
            , { position = Point3d.toVec3 startPoint, normal = Vector3d.toVec3 leftNormal }
            , { position = Point3d.toVec3 startPoint, normal = Vector3d.toVec3 rightNormal }
            )
    in
    firstFace :: secondFace :: accumulated


edgeKey : Int -> Int -> Int -> Int
edgeKey numVertices i j =
    if i < j then
        i * numVertices + j

    else
        j * numVertices + i


updateShadowEdge : Int -> Int -> Point3d Meters coordinates -> Point3d Meters coordinates -> Vector3d Unitless coordinates -> Maybe (ShadowEdge coordinates) -> Maybe (ShadowEdge coordinates)
updateShadowEdge i j pi pj normalVector currentEntry =
    case currentEntry of
        Nothing ->
            if i < j then
                Just
                    { startPoint = pi
                    , endPoint = pj
                    , leftNormal = normalVector
                    , rightNormal = Vector3d.zero
                    }

            else
                Just
                    { startPoint = pj
                    , endPoint = pi
                    , leftNormal = Vector3d.zero
                    , rightNormal = normalVector
                    }

        Just currentEdge ->
            if i < j then
                if currentEdge.leftNormal == Vector3d.zero then
                    if currentEdge.rightNormal == Vector3d.zero then
                        -- Degenerate edge, leave as is
                        currentEntry

                    else
                        -- Add left normal to edge
                        Just
                            { startPoint = currentEdge.startPoint
                            , endPoint = currentEdge.endPoint
                            , leftNormal = normalVector
                            , rightNormal = currentEdge.rightNormal
                            }

                else
                    -- Encountered a degenerate edge, , mark it as degenerate
                    Just
                        { startPoint = currentEdge.startPoint
                        , endPoint = currentEdge.endPoint
                        , leftNormal = Vector3d.zero
                        , rightNormal = Vector3d.zero
                        }

            else if currentEdge.rightNormal == Vector3d.zero then
                if currentEdge.leftNormal == Vector3d.zero then
                    -- Degenerate edge, leave as is
                    currentEntry

                else
                    -- Add right normal to edge
                    Just
                        { startPoint = currentEdge.startPoint
                        , endPoint = currentEdge.endPoint
                        , leftNormal = currentEdge.leftNormal
                        , rightNormal = normalVector
                        }

            else
                -- Found a degenerate edge, mark it as degenerate
                Just
                    { startPoint = currentEdge.startPoint
                    , endPoint = currentEdge.endPoint
                    , leftNormal = Vector3d.zero
                    , rightNormal = Vector3d.zero
                    }
