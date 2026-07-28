import Foundation

enum RequestFieldMutationError: LocalizedError, Equatable {
    case targetNotFound(String)
    case invalidBody

    var errorDescription: String? {
        switch self {
        case let .targetNotFound(id): return "Request field no longer exists: \(id)"
        case .invalidBody: return "Request body is not valid for the requested mutation"
        }
    }
}

struct RequestFieldExtractor {
    static func fields(in request: HTTPRequest) -> [PluginRequestField] {
        var result = queryFields(path: request.path)
        let contentType = request.headers.first {
            $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.1.lowercased() ?? ""

        if contentType.contains("application/x-www-form-urlencoded") {
            result.append(contentsOf: formFields(body: request.body))
        } else if contentType.contains("application/json") || looksLikeJSON(request.body) {
            result.append(contentsOf: jsonFields(body: request.body))
        }
        return result
    }

    static func applying(_ mutation: PluginMutation, to request: HTTPRequest) throws -> HTTPRequest {
        let target = fields(in: request).first { $0.id == mutation.targetID }
        guard let target else {
            throw RequestFieldMutationError.targetNotFound(mutation.targetID)
        }
        var mutated = request
        switch target.location {
        case .query:
            mutated.path = try replaceParameter(
                in: request.path,
                targetID: target.id,
                replacement: mutation.replacement,
                prefix: "query"
            )
        case .form:
            mutated.body = try replaceParameter(
                in: request.body,
                targetID: target.id,
                replacement: mutation.replacement,
                prefix: "form"
            )
        case .json:
            mutated.body = try replaceJSON(
                body: request.body,
                pointer: target.path,
                replacement: mutation.replacement
            )
        }
        return recomputingContentLength(mutated)
    }

    static func applying(_ mutations: [PluginMutation], to request: HTTPRequest) throws -> HTTPRequest {
        try mutations.reduce(request) { try applying($1, to: $0) }
    }

    static func recomputingContentLength(_ request: HTTPRequest) -> HTTPRequest {
        var result = request
        result.headers.removeAll { $0.0.caseInsensitiveCompare("Content-Length") == .orderedSame }
        if !result.body.isEmpty {
            result.headers.append(("Content-Length", String(result.body.lengthOfBytes(using: .utf8))))
        } else if ["POST", "PUT", "PATCH"].contains(result.method.uppercased()) {
            result.headers.append(("Content-Length", "0"))
        }
        return result
    }

    private static func queryFields(path: String) -> [PluginRequestField] {
        guard let question = path.firstIndex(of: "?") else { return [] }
        let afterQuestion = path.index(after: question)
        let rest = String(path[afterQuestion...])
        let query = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return parameterFields(text: query, prefix: "query", location: .query)
    }

    private static func formFields(body: String) -> [PluginRequestField] {
        parameterFields(text: body, prefix: "form", location: .form)
    }

    private static func parameterFields(
        text: String,
        prefix: String,
        location: PluginRequestField.Location
    ) -> [PluginRequestField] {
        text.split(separator: "&", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, part -> PluginRequestField? in
                let raw = String(part)
                guard !raw.isEmpty else { return nil }
                let pieces = raw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let rawName = String(pieces[0])
                let rawValue = pieces.count > 1 ? String(pieces[1]) : ""
                let name = decodeFormComponent(rawName)
                let value = decodeFormComponent(rawValue)
                return PluginRequestField(
                    id: "\(prefix):\(index)",
                    location: location,
                    name: name,
                    path: "\(prefix)[\(index)].\(name)",
                    value: value
                )
            }
    }

    private static func replaceParameter(
        in text: String,
        targetID: String,
        replacement: String,
        prefix: String
    ) throws -> String {
        guard let index = Int(targetID.split(separator: ":").last ?? "") else {
            throw RequestFieldMutationError.targetNotFound(targetID)
        }

        if prefix == "query" {
            guard let question = text.firstIndex(of: "?") else {
                throw RequestFieldMutationError.targetNotFound(targetID)
            }
            let before = String(text[...question])
            let afterQuestion = text.index(after: question)
            let rest = String(text[afterQuestion...])
            let fragmentParts = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let query = String(fragmentParts[0])
            let fragment = fragmentParts.count > 1 ? "#" + fragmentParts[1] : ""
            return before + (try replaceParameterList(query, index: index, replacement: replacement)) + fragment
        }
        return try replaceParameterList(text, index: index, replacement: replacement)
    }

    private static func replaceParameterList(_ text: String, index: Int, replacement: String) throws -> String {
        var parts = text.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        guard parts.indices.contains(index) else {
            throw RequestFieldMutationError.targetNotFound("parameter:\(index)")
        }
        let pieces = parts[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let encoded = encodeFormComponent(replacement)
        parts[index] = pieces.count > 1 ? "\(pieces[0])=\(encoded)" : "\(pieces[0])=\(encoded)"
        return parts.joined(separator: "&")
    }

    private static func jsonFields(body: String) -> [PluginRequestField] {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var fields: [PluginRequestField] = []
        enumerateJSON(object, pointer: "", displayPath: "$", keyName: "", fields: &fields)
        return fields
    }

    private static func enumerateJSON(
        _ value: Any,
        pointer: String,
        displayPath: String,
        keyName: String,
        fields: inout [PluginRequestField]
    ) {
        if let object = value as? [String: Any] {
            for key in object.keys.sorted() {
                let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                enumerateJSON(
                    object[key] as Any,
                    pointer: pointer + "/" + escaped,
                    displayPath: displayPath + "." + key,
                    keyName: key,
                    fields: &fields
                )
            }
        } else if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                enumerateJSON(
                    item,
                    pointer: pointer + "/\(index)",
                    displayPath: displayPath + "[\(index)]",
                    keyName: keyName,
                    fields: &fields
                )
            }
        } else if let string = value as? String {
            fields.append(
                PluginRequestField(
                    id: "json:\(pointer)",
                    location: .json,
                    name: keyName,
                    path: pointer,
                    value: string
                )
            )
        }
    }

    private static func replaceJSON(body: String, pointer: String, replacement: String) throws -> String {
        guard let data = body.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) else {
            throw RequestFieldMutationError.invalidBody
        }
        let components = pointer.split(separator: "/", omittingEmptySubsequences: true).map {
            String($0).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
        guard setJSONValue(&object, components: ArraySlice(components), replacement: replacement) else {
            throw RequestFieldMutationError.targetNotFound("json:\(pointer)")
        }
        let output = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: output, encoding: .utf8) else {
            throw RequestFieldMutationError.invalidBody
        }
        return string
    }

    private static func setJSONValue(
        _ value: inout Any,
        components: ArraySlice<String>,
        replacement: String
    ) -> Bool {
        guard let head = components.first else {
            value = replacement
            return true
        }
        let tail = components.dropFirst()
        if var object = value as? [String: Any], var child = object[head] {
            guard setJSONValue(&child, components: tail, replacement: replacement) else { return false }
            object[head] = child
            value = object
            return true
        }
        if var array = value as? [Any], let index = Int(head), array.indices.contains(index) {
            var child = array[index]
            guard setJSONValue(&child, components: tail, replacement: replacement) else { return false }
            array[index] = child
            value = array
            return true
        }
        return false
    }

    private static func looksLikeJSON(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func decodeFormComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private static func encodeFormComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
