//
//  Query.swift
//  LeanCloud
//
//  Created by Tang Tianyong on 4/19/16.
//  Copyright © 2016 LeanCloud. All rights reserved.
//

import Foundation

final public class Query {
    /// Query class name.
    public private(set) var className: String

    /// The limit on the number of objects to return.
    public var limit: Int?

    /// The number of objects to skip before returning.
    public var skip: Int?

    /// Included keys.
    private var includedKeys: Set<String> = []

    /// Selected keys.
    private var selectedKeys: Set<String> = []

    /// Equality table.
    private var equalityTable: [String: LCType] = [:]

    /// Equality key-value pairs.
    private var equalityPairs: [[String: LCType]] {
        return equalityTable.map { [$0: $1] }
    }

    /// Ordered keys.
    private var orderedKeys: String?

    /// Dictionary of constraints indexed by key.
    /// Note that it may contains LCType or Query value.
    private var constraintDictionary: [String: AnyObject] = [:]

    /// JSON string of constraint dictionary.
    private var constraintJSONString: String {
        let JSONValue = ObjectProfiler.JSONValue(constraintDictionary)
        let data = try! NSJSONSerialization.dataWithJSONObject(JSONValue, options: NSJSONWritingOptions(rawValue: 0))

        return String(data: data, encoding: NSUTF8StringEncoding)!
    }

    // The JSON value of query.
    // It will replace all LCType and Query values in dictionary with corresponding JSON value.
    private var JSONValue: [String: AnyObject] {
        var dictionary: [String: AnyObject] = [:]

        dictionary["className"] = className

        if !constraintDictionary.isEmpty {
            dictionary["where"] = constraintJSONString
        }
        if !includedKeys.isEmpty {
            dictionary["include"] = includedKeys.joinWithSeparator(",")
        }
        if !selectedKeys.isEmpty {
            dictionary["keys"] = selectedKeys.joinWithSeparator(",")
        }
        if let orderedKeys = orderedKeys {
            dictionary["order"] = orderedKeys
        }
        if let limit = limit {
            dictionary["limit"] = limit
        }
        if let skip = skip {
            dictionary["skip"] = skip
        }

        return dictionary
    }

    /**
     Constraint for key.
     */
    public enum Constraint {
        case Included
        case Selected
        case Existed
        case NotExisted

        case EqualTo(value: LCType)
        case NotEqualTo(value: LCType)
        case LessThan(value: LCType)
        case LessThanOrEqualTo(value: LCType)
        case GreaterThan(value: LCType)
        case GreaterThanOrEqualTo(value: LCType)

        case ContainedIn(array: LCArray)
        case NotContainedIn(array: LCArray)
        case ContainedAllIn(array: LCArray)
        case EqualToSize(size: LCNumber)

        case NearbyPoint(point: LCGeoPoint)
        case NearbyPointWithRange(point: LCGeoPoint, from: LCGeoPoint.Distance?, to: LCGeoPoint.Distance?)
        case NearbyPointWithRectangle(southwest: LCGeoPoint, northeast: LCGeoPoint)

        case MatchedQuery(query: Query)
        case NotMatchedQuery(query: Query)
        case MatchedQueryAndKey(query: Query, key: String)
        case NotMatchedQueryAndKey(query: Query, key: String)

        case MatchedPattern(pattern: String, option: String?)
        case MatchedSubstring(string: String)
        case PrefixedBy(string: String)
        case SuffixedBy(string: String)

        case Ascending
        case Descending
    }

    var endpoint: String {
        return ObjectProfiler.objectClass(className).classEndpoint()
    }

    /**
     Construct query with class name.

     - parameter className: The class name to query.
     */
    public init(className: String) {
        self.className = className
    }

    /**
     Add constraint in query.

     - parameter constraint: The constraint.
     */
    public func whereKey(key: String, _ constraint: Constraint) {
        var dictionary: [String: AnyObject]?

        switch constraint {
        /* Key matching. */
        case .Included:
            includedKeys.insert(key)
        case .Selected:
            selectedKeys.insert(key)
        case .Existed:
            dictionary = ["$exists": true]
        case .NotExisted:
            dictionary = ["$exists": false]

        /* Equality matching. */
        case let .EqualTo(value):
            equalityTable[key] = value
            constraintDictionary["$and"] = equalityPairs
        case let .NotEqualTo(value):
            dictionary = ["$ne": value]
        case let .LessThan(value):
            dictionary = ["$lt": value]
        case let .LessThanOrEqualTo(value):
            dictionary = ["$lte": value]
        case let .GreaterThan(value):
            dictionary = ["$gt": value]
        case let .GreaterThanOrEqualTo(value):
            dictionary = ["$gte": value]

        /* Array matching. */
        case let .ContainedIn(array):
            dictionary = ["$in": array]
        case let .NotContainedIn(array):
            dictionary = ["$nin": array]
        case let .ContainedAllIn(array):
            dictionary = ["$all": array]
        case let .EqualToSize(size):
            dictionary = ["$size": size]

        /* Geography point matching. */
        case let .NearbyPoint(point):
            dictionary = ["$nearSphere": point]
        case let .NearbyPointWithRange(point, min, max):
            var value: [String: AnyObject] = ["$nearSphere": point]
            if let min = min { value["$minDistanceIn\(min.unit.rawValue)"] = min.value }
            if let max = max { value["$maxDistanceIn\(max.unit.rawValue)"] = max.value }
            dictionary = value
        case let .NearbyPointWithRectangle(southwest, northeast):
            dictionary = ["$within": ["$box": [southwest, northeast]]]

        /* Query matching. */
        case let .MatchedQuery(query):
            dictionary = ["$inQuery": query]
        case let .NotMatchedQuery(query):
            dictionary = ["$notInQuery": query]
        case let .MatchedQueryAndKey(query, key):
            dictionary = ["$select": ["query": query, "key": key]]
        case let .NotMatchedQueryAndKey(query, key):
            dictionary = ["$dontSelect": ["query": query, "key": key]]

        /* String matching. */
        case let .MatchedPattern(pattern, option):
            dictionary = ["$regex": pattern, "option": option ?? ""]
        case let .MatchedSubstring(string):
            dictionary = ["$regex": "\(string.regularEscapedString)"]
        case let .PrefixedBy(string):
            dictionary = ["$regex": "^\(string.regularEscapedString)"]
        case let .SuffixedBy(string):
            dictionary = ["$regex": "\(string.regularEscapedString)$"]

        case .Ascending:
            appendOrderedKey(key)
        case .Descending:
            appendOrderedKey("-\(key)")
        }

        if let dictionary = dictionary {
            addConstraint(key, dictionary)
        }
    }

    /**
     Append ordered key to ordered keys string.

     - parameter orderedKey: The ordered key with optional '-' prefixed.
     */
    func appendOrderedKey(orderedKey: String) {
        orderedKeys = orderedKeys?.stringByAppendingString(orderedKey) ?? orderedKey
    }

    /**
     Add a constraint for key.

     - parameter key:        The key on which the constraint to be added.
     - parameter dictionary: The constraint dictionary for key.
     */
    func addConstraint(key: String, _ dictionary: [String: AnyObject]) {
        constraintDictionary[key] = dictionary
    }

    /**
     Transform JSON results to objects.

     - parameter results: The results return by query.

     - returns: An array of LCObject objects.
     */
    func processResults(results: [AnyObject], className: String?) -> [LCObject] {
        return results.map { dictionary in
            let object = ObjectProfiler.object(className: className ?? self.className)
            ObjectProfiler.updateObject(object, dictionary)
            return object
        }
    }

    /**
     Query objects synchronously.

     - returns: The response of the query request.
     */
    public func find() -> (Response, [LCObject]) {
        var objects: [LCObject] = []
        let response = RESTClient.request(.GET, endpoint, parameters: JSONValue)

        if response.isSuccess {
            if let results = response.value?["results"] as? [AnyObject] {
                objects = processResults(results, className: response.value?["className"] as? String)
            }
        }

        return (response, objects)
    }
}