module obj;

/**
    Parser for Wavefront OBJ files.
*/

import std.experimental.logger;
import std.exception : enforce;
import gl3n.linalg;

struct MtlData {
    string name;
    vec3   ambientLight;
    vec3   diffuseLight;
    vec3   specularLight;
    ulong  firstIndex;
    ulong  numIndices;
}

struct ObjData {
    vec3[]    positions;
    vec3[]    normals;
    vec2[]    texcoords;
    //MtlData[] materials;
}

ObjData parseObj(string objFilePath) {
    import std.stdio  : File;
    File objFile = File(objFilePath);

    import std.string    : strip, split, startsWith;
    import std.algorithm : map;

    Vector!(float, N) stringsToVec(int N)(string[] splitString) 
    {
        import std.format;
        enforce(splitString.length == N, "Vector must have %s components".format(N));
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

    foreach (splitLine; objFile.byLineCopy.map!(strip)
                                          .map!(s => s.split(" "))) 
    {
        debug log("Parsing line: ", splitLine);
        if (splitLine.length == 0 || splitLine[0].startsWith("#")) {
            continue;
        }

        final switch (splitLine[0]) {
            case "v" : uniquePositions ~= stringsToVec!3(splitLine[1 .. $]); break;
            case "vn": uniqueNormals   ~= stringsToVec!3(splitLine[1 .. $]); break;
            case "vt": uniqueTexcoords ~= stringsToVec!2(splitLine[1 .. $]); break;

            case "f" :  
                foreach (string face; splitLine[1 .. $]) {
                    // face will be a string like "1/2/3" or "1//3"

                    debug log("Parsing face: ", face);

                    import std.conv : to;
                    auto indices = face.split("/").map!(s => s.to!ulong)
                                                  .map!(i => i-1);

                    debug log("  -> Got indices ", indices);

                    enforce(indices.length == 2 || indices.length == 3);

                    enforce(indices[0] < uniquePositions.length);
                    ret.positions ~= uniquePositions[indices[0]];

                    if (indices.length == 2) {
                        enforce(indices[1] < uniqueNormals.length);
                        ret.normals ~= uniqueNormals[indices[1]];
                    } else if (indices.length == 3) {
                        enforce(indices[1] < uniqueTexcoords.length);
                        enforce(indices[2] < uniqueNormals.length);
                        ret.texcoords ~= uniqueTexcoords[indices[1]];
                        ret.normals   ~= uniqueNormals[indices[2]];
                    } else {
                        assert(0);
                    }
                }
                break;
            case "mtllib": break;
            case "usemtl": break;
            case "g"     : break;
            case "o"     : break;
            case "s"     : break;
        }
    }

    return ret;
}

