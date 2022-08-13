module obj;

/**
    Parser for Wavefront OBJ files.
*/

import std.exception : enforce;
import std.experimental.logger : log;

import math;

struct ObjData {
    v3[] positions;
    v3[] normals;
    v2[] texcoords;
}

ObjData parseObj(string objFilePath) {
    import std.stdio  : File;
    File objFile = File(objFilePath);

    import std.string    : strip, split, startsWith;
    import std.algorithm : map;

    Vector!(float, N) stringsToVec(int N)(string[] splitString)
    {
        import std.format : format;
        enforce(splitString.length == N, "Vector must have %s components. Input was %s".format(N, splitString));
        import std.conv : to;
        Vector!(float, N) ret;
        foreach (i; 0 .. N) {
            ret.vector[i] = splitString[i].to!float;
        }
        return ret;
    }

    vec3[] uniquePositions;
    vec3[] uniqueNormals;
    vec2[] uniqueTexcoords;

    ObjData ret;

    foreach (splitLine; objFile.byLineCopy.map!(strip).map!(split))
    {
        debug log("Parsing line: ", splitLine);

        if (splitLine.length == 0 || splitLine[0].startsWith("#")) {
            continue;
        }

        assert(splitLine.length > 1);

        auto token = splitLine[0];
        auto rest  = splitLine[1 .. $];

        final switch (token)
        {
        case "v" : uniquePositions ~= stringsToVec!3(rest); break;
        case "vn": uniqueNormals   ~= stringsToVec!3(rest); break;
        case "vt": uniqueTexcoords ~= stringsToVec!2(rest); break;

        case "f" : {

            /*
                Handle quads by converting them into two triangles assuming
                a certain vertex winding.
            */

            const numFaces = splitLine[1 .. $].length;
            const f = splitLine[1 .. $];
            string[] faces;

            if (numFaces == 4) {
                // then we're dealing with quads
                faces.length = 6;
                faces = [
                    /* This is assuming a certain winding! */
                    /* triangle 1 */ f[0], f[1], f[2],
                    /* triangle 2 */ f[0], f[2], f[3],
                ];
            } else {
                // only triangles or quads supported
                assert(numFaces == 3);
                faces.length = 3;
                faces = splitLine[1 .. $];
            }

            foreach (string face; faces) {
                // face will be a string like "1/2/3" or "1//3"

                debug log("Parsing face: ", face);

                size_t interpretIndex(T)(T idx, size_t arrLen) pure {
                    return (idx < 0) ? arrLen + idx : idx - 1;
                }

                import std.conv : to;
                auto indices = face.split("/").map!(s => s.to!long);

                debug log("  -> Got indices ", indices);

                enforce(indices.length == 3);

                size_t vi = interpretIndex(indices[0], uniquePositions.length);
                size_t ti = interpretIndex(indices[1], uniqueTexcoords.length);
                size_t ni = interpretIndex(indices[2], uniqueNormals.length);

                auto v = uniquePositions[vi];
                auto t = uniqueTexcoords[ti];
                auto n = uniqueNormals[ni];

                debug log("  -> v = ", v);
                debug log("  -> t = ", t);
                debug log("  -> n = ", n);

                ret.positions ~= v;
                ret.texcoords ~= t;
                ret.normals   ~= n;
            }
            break;
        }
        case "mtllib": break;
        case "usemtl": break;
        case "g"     : break;
        case "o"     : break;
        case "s"     : break;
        }
    }

    return ret;
}

