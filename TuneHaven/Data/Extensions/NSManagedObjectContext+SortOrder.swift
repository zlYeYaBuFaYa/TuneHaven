import CoreData

extension NSManagedObjectContext {
    func maxSortOrder(forEntity entityName: String, predicate: NSPredicate? = nil) throws -> Int {
        let request: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        let expr = NSExpression(forKeyPath: "sortOrder")
        let maxExpr = NSExpression(forFunction: "max:", arguments: [expr])
        let desc = NSExpressionDescription()
        desc.name = "maxSortOrder"
        desc.expression = maxExpr
        desc.expressionResultType = .integer32AttributeType
        request.propertiesToFetch = [desc]
        let results = try self.fetch(request)
        return (results.first?["maxSortOrder"] as? Int) ?? 0
    }

    func softDeletedSongIds() throws -> [UUID] {
        let req: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "SongEntity")
        req.resultType = .dictionaryResultType
        req.predicate = NSPredicate(format: "softDeleted == YES")
        req.propertiesToFetch = ["id"]
        let results = try fetch(req)
        return results.compactMap { $0["id"] as? UUID }
    }
}
