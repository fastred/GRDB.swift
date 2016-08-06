extension Database {
    /// Creates a database table.
    ///
    ///     try db.create(table: "pointOfInterests") { t in
    ///         t.column("id", .Integer).primaryKey()
    ///         t.column("title", .Text)
    ///         t.column("favorite", .Boolean).notNull().default(false)
    ///         t.column("longitude", .Double).notNull()
    ///         t.column("latitude", .Double).notNull()
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html and
    /// https://www.sqlite.org/withoutrowid.html
    ///
    /// - parameters:
    ///     - name: The table name.
    ///     - temporary: If true, creates a temporary table.
    ///     - ifNotExists: If false, no error is thrown if table already exists.
    ///     - withoutRowID: If true, uses WITHOUT ROWID optimization.
    ///     - body: A closure that defines table columns and constraints.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @available(iOS 8.2, OSX 10.10, *)
    public func create(table name: String, temporary: Bool = false, ifNotExists: Bool = false, withoutRowID: Bool, body: (SQLTableBuilder) -> Void) throws {
        // WITHOUT ROWID was added in SQLite 3.8.2 http://www.sqlite.org/changes.html#version_3_8_2
        // It is available from iOS 8.2 and OS X 10.10 https://github.com/yapstudios/YapDatabase/wiki/SQLite-version-(bundled-with-OS)
        let builder = SQLTableBuilder(name: name, temporary: temporary, ifNotExists: ifNotExists, withoutRowID: withoutRowID)
        body(builder)
        let sql = try builder.sql(self)
        try execute(sql)
    }

    /// Creates a database table.
    ///
    ///     try db.create(table: "pointOfInterests") { t in
    ///         t.column("id", .Integer).primaryKey()
    ///         t.column("title", .Text)
    ///         t.column("favorite", .Boolean).notNull().default(false)
    ///         t.column("longitude", .Double).notNull()
    ///         t.column("latitude", .Double).notNull()
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html
    ///
    /// - parameters:
    ///     - name: The table name.
    ///     - temporary: If true, creates a temporary table.
    ///     - ifNotExists: If false, no error is thrown if table already exists.
    ///     - body: A closure that defines table columns and constraints.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public func create(table name: String, temporary: Bool = false, ifNotExists: Bool = false, body: (SQLTableBuilder) -> Void) throws {
        let builder = SQLTableBuilder(name: name, temporary: temporary, ifNotExists: ifNotExists, withoutRowID: false)
        body(builder)
        let sql = try builder.sql(self)
        try execute(sql)
    }
    
    /// Renames a database table.
    ///
    /// See https://www.sqlite.org/lang_altertable.html
    ///
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public func rename(table name: String, to newName: String) throws {
        try execute("ALTER TABLE \(name.quotedDatabaseIdentifier) RENAME TO \(newName.quotedDatabaseIdentifier)")
    }
    
    /// Modifies a database table.
    ///
    ///     try db.alter(table: "persons") { t in
    ///         t.add(column: "url", .Text)
    ///     }
    ///
    /// See https://www.sqlite.org/lang_altertable.html
    ///
    /// - parameters:
    ///     - name: The table name.
    ///     - body: A closure that defines table alterations.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public func alter(table name: String, body: (SQLTableAlterationBuilder) -> Void) throws {
        let builder = SQLTableAlterationBuilder(name: name)
        body(builder)
        let sql = try builder.sql(self)
        try execute(sql)
    }
    
    /// Deletes a database table.
    ///
    /// See https://www.sqlite.org/lang_droptable.html
    ///
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public func drop(table name: String) throws {
        try execute("DROP TABLE \(name.quotedDatabaseIdentifier)")
    }
    
    /// Creates a database index.
    ///
    ///     try db.create(index: "personByEmail", on: "person", columns: ["email"])
    ///
    /// SQLite can also index expressions (https://www.sqlite.org/expridx.html)
    /// and use specific collations. To create such an index, use a raw SQL
    /// query.
    ///
    ///     try db.execute("CREATE INDEX ...")
    ///
    /// See https://www.sqlite.org/lang_createindex.html
    ///
    /// - parameters:
    ///     - name: The index name.
    ///     - table: The name of the indexed table.
    ///     - columns: The indexed columns.
    ///     - unique: If true, creates a unique index.
    ///     - ifNotExists: If false, no error is thrown if index already exists.
    ///     - condition: If not nil, creates a partial index
    ///       (see https://www.sqlite.org/partialindex.html).
    public func create(index name: String, on table: String, columns: [String], unique: Bool = false, ifNotExists: Bool = false, condition: _SQLExpressible? = nil) throws {
        let builder = IndexBuilder(name: name, table: table, columns: columns, unique: unique, ifNotExists: ifNotExists, condition: condition?.sqlExpression)
        let sql = builder.sql()
        try execute(sql)
    }
    
    /// Deletes a database index.
    ///
    /// See https://www.sqlite.org/lang_dropindex.html
    ///
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    public func drop(index name: String) throws {
        try execute("DROP INDEX \(name.quotedDatabaseIdentifier)")
    }
}

/// The SQLTableBuilder class lets you define table columns and constraints.
///
/// You don't create instances of this class. Instead, you use the Database
/// `create(table:)` method:
///
///     try db.create(table: "persons") { t in // t is SQLTableBuilder
///         t.column(...)
///     }
///
/// See https://www.sqlite.org/lang_createtable.html
public final class SQLTableBuilder {
    let name: String
    let temporary: Bool
    let ifNotExists: Bool
    let withoutRowID: Bool
    var columns: [SQLColumnBuilder] = []
    var primaryKeyConstraint: (columns: [String], conflictResolution: SQLConflictResolution?)?
    var uniqueKeyConstraints: [(columns: [String], conflictResolution: SQLConflictResolution?)] = []
    var foreignKeyConstraints: [(columns: [String], table: String, destinationColumns: [String]?, deleteAction: SQLForeignKeyAction?, updateAction: SQLForeignKeyAction?, deferred: Bool)] = []
    var checkConstraints: [_SQLExpression] = []
    
    init(name: String, temporary: Bool, ifNotExists: Bool, withoutRowID: Bool) {
        self.name = name
        self.temporary = temporary
        self.ifNotExists = ifNotExists
        self.withoutRowID = withoutRowID
    }
    
    /// Appends a table column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text)
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#tablecoldef
    ///
    /// - parameter name: the column name.
    /// - parameter type: the column type.
    /// - returns: An SQLColumnBuilder that allows you to refine the
    ///   column definition.
    public func column(name: String, _ type: SQLColumnType) -> SQLColumnBuilder {
        let column = SQLColumnBuilder(name: name, type: type)
        columns.append(column)
        return column
    }
    
    /// Defines the table primary key.
    ///
    ///     try db.create(table: "citizenships") { t in
    ///         t.column("personID", .Integer)
    ///         t.column("countryCode", .Text)
    ///         t.primaryKey(["personID", "countryCode"])
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#primkeyconst and
    /// https://www.sqlite.org/lang_createtable.html#rowid
    ///
    /// - parameter columns: The primary key columns.
    /// - parameter conflitResolution: An optional conflict resolution
    ///   (see https://www.sqlite.org/lang_conflict.html).
    public func primaryKey(columns: [String], onConflict conflictResolution: SQLConflictResolution? = nil) {
        guard primaryKeyConstraint == nil else {
            fatalError("can't define several primary keys")
        }
        primaryKeyConstraint = (columns: columns, conflictResolution: conflictResolution)
    }
    
    /// Adds a unique key.
    ///
    ///     try db.create(table: "pointOfInterests") { t in
    ///         t.column("latitude", .Double)
    ///         t.column("longitude", .Double)
    ///         t.uniqueKey(["latitude", "longitude"])
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#uniqueconst
    ///
    /// - parameter columns: The unique key columns.
    /// - parameter conflitResolution: An optional conflict resolution
    ///   (see https://www.sqlite.org/lang_conflict.html).
    public func uniqueKey(columns: [String], onConflict conflictResolution: SQLConflictResolution? = nil) {
        uniqueKeyConstraints.append((columns: columns, conflictResolution: conflictResolution))
    }
    
    /// Adds a foreign key.
    ///
    ///     try db.create(table: "passport") { t in
    ///         t.column("issueDate", .Date)
    ///         t.column("personID", .Integer)
    ///         t.column("countryCode", .Text)
    ///         t.foreignKey(["personID", "countryCode"], references: "citizenships", onDelete: .Cascade)
    ///     }
    ///
    /// See https://www.sqlite.org/foreignkeys.html
    ///
    /// - parameters:
    ///     - columns: The foreign key columns.
    ///     - table: The referenced table.
    ///     - destinationColumns: The columns in the referenced table. If not
    ///       specified, the columns of the primary key of the referenced table
    ///       are used.
    ///     - deleteAction: Optional action when the referenced row is deleted.
    ///     - updateAction: Optional action when the referenced row is updated.
    ///     - deferred: If true, defines a deferred foreign key constraint.
    ///       See https://www.sqlite.org/foreignkeys.html#fk_deferred.
    public func foreignKey(columns: [String], references table: String, columns destinationColumns: [String]? = nil, onDelete deleteAction: SQLForeignKeyAction? = nil, onUpdate updateAction: SQLForeignKeyAction? = nil, deferred: Bool = false) {
        foreignKeyConstraints.append((columns: columns, table: table, destinationColumns: destinationColumns, deleteAction: deleteAction, updateAction: updateAction, deferred: deferred))
    }
    
    /// Adds a CHECK constraint.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("personalPhone", .Text)
    ///         t.column("workPhone", .Text)
    ///         let personalPhone = SQLColumn("personalPhone")
    ///         let workPhone = SQLColumn("workPhone")
    ///         t.check(personalPhone != nil || workPhone != nil)
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#ckconst
    ///
    /// - parameter condition: The checked condition
    public func check(condition: _SQLExpressible) {
        checkConstraints.append(condition.sqlExpression)
    }
    
    /// Adds a CHECK constraint.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("personalPhone", .Text)
    ///         t.column("workPhone", .Text)
    ///         t.check(sql: "personalPhone IS NOT NULL OR workPhone IS NOT NULL")
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#ckconst
    ///
    /// - parameter sql: An SQL snippet
    public func check(sql sql: String) {
        checkConstraints.append(_SQLExpression.Literal(sql, nil))
    }
    
    private func sql(db: Database) throws -> String {
        var chunks: [String] = []
        chunks.append("CREATE")
        if temporary {
            chunks.append("TEMPORARY")
        }
        chunks.append("TABLE")
        if ifNotExists {
            chunks.append("IF NOT EXISTS")
        }
        chunks.append(name.quotedDatabaseIdentifier)
        
        do {
            var items: [String] = []
            try items.appendContentsOf(columns.map { try $0.sql(db) })
            
            if let (columns, conflictResolution) = primaryKeyConstraint {
                var chunks: [String] = []
                chunks.append("PRIMARY KEY")
                chunks.append("(\((columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
                if let conflictResolution = conflictResolution {
                    chunks.append("ON CONFLICT")
                    chunks.append(conflictResolution.rawValue)
                }
                items.append(chunks.joinWithSeparator(" "))
            }
            
            for (columns, conflictResolution) in uniqueKeyConstraints {
                var chunks: [String] = []
                chunks.append("UNIQUE")
                chunks.append("(\((columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
                if let conflictResolution = conflictResolution {
                    chunks.append("ON CONFLICT")
                    chunks.append(conflictResolution.rawValue)
                }
                items.append(chunks.joinWithSeparator(" "))
            }
            
            for (columns, table, destinationColumns, deleteAction, updateAction, deferred) in foreignKeyConstraints {
                var chunks: [String] = []
                chunks.append("FOREIGN KEY")
                chunks.append("(\((columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
                chunks.append("REFERENCES")
                if let destinationColumns = destinationColumns {
                    chunks.append("\(table.quotedDatabaseIdentifier)(\((destinationColumns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
                } else if let primaryKey = try db.primaryKey(table) {
                    chunks.append("\(table.quotedDatabaseIdentifier)(\((primaryKey.columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
                } else {
                    fatalError("explicit referenced column(s) required, since table \(table) has no primary key")
                }
                if let deleteAction = deleteAction {
                    chunks.append("ON DELETE")
                    chunks.append(deleteAction.rawValue)
                }
                if let updateAction = updateAction {
                    chunks.append("ON UPDATE")
                    chunks.append(updateAction.rawValue)
                }
                if deferred {
                    chunks.append("DEFERRABLE INITIALLY DEFERRED")
                }
                items.append(chunks.joinWithSeparator(" "))
            }
            
            for checkExpression in checkConstraints {
                var chunks: [String] = []
                chunks.append("CHECK")
                var arguments: StatementArguments? = nil // nil so that checkExpression.sql(&arguments) embeds literals
                chunks.append("(" + checkExpression.sql(&arguments) + ")")
                items.append(chunks.joinWithSeparator(" "))
            }
            
            chunks.append("(\(items.joinWithSeparator(", ")))")
        }
        
        if withoutRowID {
            chunks.append("WITHOUT ROWID")
        }
        return chunks.joinWithSeparator(" ")
    }
}

/// The SQLTableAlterationBuilder class lets you alter database tables.
///
/// You don't create instances of this class. Instead, you use the Database
/// `alter(table:)` method:
///
///     try db.alter(table: "persons") { t in // t is SQLTableAlterationBuilder
///         t.add(column: ...)
///     }
///
/// See https://www.sqlite.org/lang_altertable.html
public final class SQLTableAlterationBuilder {
    let name: String
    var addedColumns: [SQLColumnBuilder] = []
    
    init(name: String) {
        self.name = name
    }
    
    /// Appends a column to the table.
    ///
    ///     try db.alter(table: "persons") { t in
    ///         t.add(column: "url", .Text)
    ///     }
    ///
    /// See https://www.sqlite.org/lang_altertable.html
    ///
    /// - parameter name: the column name.
    /// - parameter type: the column type.
    /// - returns: An SQLColumnBuilder that allows you to refine the
    ///   column definition.
    public func add(column name: String, _ type: SQLColumnType) -> SQLColumnBuilder {
        let column = SQLColumnBuilder(name: name, type: type)
        addedColumns.append(column)
        return column
    }
    
    private func sql(db: Database) throws -> String {
        var statements: [String] = []
        
        for column in addedColumns {
            var chunks: [String] = []
            chunks.append("ALTER TABLE")
            chunks.append(name.quotedDatabaseIdentifier)
            chunks.append("ADD COLUMN")
            try chunks.append(column.sql(db))
            let statement = chunks.joinWithSeparator(" ")
            statements.append(statement)
        }
        
        return statements.joinWithSeparator("; ")
    }
}

/// The SQLColumnBuilder class lets you refine a table column.
///
/// You get instances of this class when you create or alter a database table:
///
///     try db.create(table: "persons") { t in
///         t.column(...)      // SQLColumnBuilder
///     }
///
///     try db.alter(table: "persons") { t in
///         t.add(column: ...) // SQLColumnBuilder
///     }
///
/// See https://www.sqlite.org/lang_createtable.html and
/// https://www.sqlite.org/lang_altertable.html
public final class SQLColumnBuilder {
    let name: String
    let type: SQLColumnType
    var primaryKey: (conflictResolution: SQLConflictResolution?, autoincrement: Bool)?
    var notNullConflictResolution: SQLConflictResolution?
    var uniqueConflictResolution: SQLConflictResolution?
    var checkExpression: _SQLExpression?
    var defaultExpression: _SQLExpression?
    var collationName: String?
    var reference: (table: String, column: String?, deleteAction: SQLForeignKeyAction?, updateAction: SQLForeignKeyAction?, deferred: Bool)?
    
    init(name: String, type: SQLColumnType) {
        self.name = name
        self.type = type
    }
    
    /// Adds a primary key constraint on the column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("id", .Integer).primaryKey()
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#primkeyconst and
    /// https://www.sqlite.org/lang_createtable.html#rowid
    ///
    /// - parameters:
    ///     - conflitResolution: An optional conflict resolution
    ///       (see https://www.sqlite.org/lang_conflict.html).
    ///     - autoincrement: If true, the primary key is autoincremented.
    /// - returns: Self so that you can further refine the column definition.
    public func primaryKey(onConflict conflictResolution: SQLConflictResolution? = nil, autoincrement: Bool = false) -> SQLColumnBuilder {
        primaryKey = (conflictResolution: conflictResolution, autoincrement: autoincrement)
        return self
    }
    
    /// Adds a NOT NULL constraint on the column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text).notNull()
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#notnullconst
    ///
    /// - parameter conflitResolution: An optional conflict resolution
    ///   (see https://www.sqlite.org/lang_conflict.html).
    /// - returns: Self so that you can further refine the column definition.
    public func notNull(onConflict conflictResolution: SQLConflictResolution? = nil) -> SQLColumnBuilder {
        notNullConflictResolution = conflictResolution ?? .Abort
        return self
    }
    
    /// Adds a UNIQUE constraint on the column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("email", .Text).unique()
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#uniqueconst
    ///
    /// - parameter conflitResolution: An optional conflict resolution
    ///   (see https://www.sqlite.org/lang_conflict.html).
    /// - returns: Self so that you can further refine the column definition.
    public func unique(onConflict conflictResolution: SQLConflictResolution? = nil) -> SQLColumnBuilder {
        uniqueConflictResolution = conflictResolution ?? .Abort
        return self
    }
    
    /// Adds a CHECK constraint on the column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text).check { length($0) > 0 }
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#ckconst
    ///
    /// - parameter condition: A closure whose argument is an SQLColumn that
    ///   represents the defined column, and returns the expression to check.
    /// - returns: Self so that you can further refine the column definition.
    public func check(@noescape condition: (SQLColumn) -> _SQLExpressible) -> SQLColumnBuilder {
        checkExpression = condition(SQLColumn(name)).sqlExpression
        return self
    }
    
    /// Adds a CHECK constraint on the column.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text).check(sql: "LENGTH(name) > 0")
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#ckconst
    ///
    /// - parameter sql: An SQL snippet.
    /// - returns: Self so that you can further refine the column definition.
    public func check(sql sql: String) -> SQLColumnBuilder {
        checkExpression = _SQLExpression.Literal(sql, nil)
        return self
    }
    
    /// Defines the default column value.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text).defaults("Anonymous")
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#dfltval
    ///
    /// - parameter value: A DatabaseValueConvertible value.
    /// - returns: Self so that you can further refine the column definition.
    public func defaults(value: DatabaseValueConvertible) -> SQLColumnBuilder {
        defaultExpression = value.sqlExpression
        return self
    }
    
    /// Defines the default column value.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("creationDate", .DateTime).defaults(sql: "CURRENT_TIMESTAMP")
    ///     }
    ///
    /// See https://www.sqlite.org/lang_createtable.html#dfltval
    ///
    /// - parameter sql: An SQL snippet.
    /// - returns: Self so that you can further refine the column definition.
    public func defaults(sql sql: String) -> SQLColumnBuilder {
        defaultExpression = _SQLExpression.Literal(sql, nil)
        return self
    }
    
    // Defines the default column collation.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("email", .Text).collate(.Nocase)
    ///     }
    ///
    /// See https://www.sqlite.org/datatype3.html#collation
    ///
    /// - parameter collation: An SQLCollation.
    /// - returns: Self so that you can further refine the column definition.
    public func collate(collation: SQLCollation) -> SQLColumnBuilder {
        collationName = collation.rawValue
        return self
    }
    
    // Defines the default column collation.
    ///
    ///     try db.create(table: "persons") { t in
    ///         t.column("name", .Text).collate(.localizedCaseInsensitiveCompare)
    ///     }
    ///
    /// See https://www.sqlite.org/datatype3.html#collation
    ///
    /// - parameter collation: A custom DatabaseCollation.
    /// - returns: Self so that you can further refine the column definition.
    public func collate(collation: DatabaseCollation) -> SQLColumnBuilder {
        collationName = collation.name
        return self
    }
    
    /// Defines a foreign key.
    ///
    ///     try db.create(table: "books") { t in
    ///         t.column("authorId", .Integer).references("authors", onDelete: .Cascade)
    ///     }
    ///
    /// See https://www.sqlite.org/foreignkeys.html
    ///
    /// - parameters
    ///     - table: The referenced table.
    ///     - column: The column in the referenced table. If not specified, the
    ///       column of the primary key of the referenced table is used.
    ///     - deleteAction: Optional action when the referenced row is deleted.
    ///     - updateAction: Optional action when the referenced row is updated.
    ///     - deferred: If true, defines a deferred foreign key constraint.
    ///       See https://www.sqlite.org/foreignkeys.html#fk_deferred.
    /// - returns: Self so that you can further refine the column definition.
    public func references(table: String, column: String? = nil, onDelete deleteAction: SQLForeignKeyAction? = nil, onUpdate updateAction: SQLForeignKeyAction? = nil, deferred: Bool = false) -> SQLColumnBuilder {
        reference = (table: table, column: column, deleteAction: deleteAction, updateAction: updateAction, deferred: deferred)
        return self
    }
    
    private func sql(db: Database) throws -> String {
        var chunks: [String] = []
        chunks.append(name.quotedDatabaseIdentifier)
        chunks.append(type.rawValue)
        
        if let (conflictResolution, autoincrement) = primaryKey {
            chunks.append("PRIMARY KEY")
            if let conflictResolution = conflictResolution {
                chunks.append("ON CONFLICT")
                chunks.append(conflictResolution.rawValue)
            }
            if autoincrement {
                chunks.append("AUTOINCREMENT")
            }
        }
        
        switch notNullConflictResolution {
        case .None:
            break
        case .Abort?:
            chunks.append("NOT NULL")
        case let conflictResolution?:
            chunks.append("NOT NULL ON CONFLICT")
            chunks.append(conflictResolution.rawValue)
        }
        
        switch uniqueConflictResolution {
        case .None:
            break
        case .Abort?:
            chunks.append("UNIQUE")
        case let conflictResolution?:
            chunks.append("UNIQUE ON CONFLICT")
            chunks.append(conflictResolution.rawValue)
        }
        
        if let checkExpression = checkExpression {
            chunks.append("CHECK")
            var arguments: StatementArguments? = nil // nil so that checkExpression.sql(&arguments) embeds literals
            chunks.append("(" + checkExpression.sql(&arguments) + ")")
        }
        
        if let defaultExpression = defaultExpression {
            var arguments: StatementArguments? = nil // nil so that defaultExpression.sql(&arguments) embeds literals
            chunks.append("DEFAULT")
            chunks.append(defaultExpression.sql(&arguments))
        }
        
        if let collationName = collationName {
            chunks.append("COLLATE")
            chunks.append(collationName)
        }
        
        if let (table, column, deleteAction, updateAction, deferred) = reference {
            chunks.append("REFERENCES")
            if let column = column {
                chunks.append("\(table.quotedDatabaseIdentifier)(\(column.quotedDatabaseIdentifier))")
            } else if let primaryKey = try db.primaryKey(table) {
                chunks.append("\(table.quotedDatabaseIdentifier)(\((primaryKey.columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
            } else {
                fatalError("explicit referenced column required, since table \(table) has no primary key")
            }
            if let deleteAction = deleteAction {
                chunks.append("ON DELETE")
                chunks.append(deleteAction.rawValue)
            }
            if let updateAction = updateAction {
                chunks.append("ON UPDATE")
                chunks.append(updateAction.rawValue)
            }
            if deferred {
                chunks.append("DEFERRABLE INITIALLY DEFERRED")
            }
        }
        
        return chunks.joinWithSeparator(" ")
    }
}

private struct IndexBuilder {
    let name: String
    let table: String
    let columns: [String]
    let unique: Bool
    let ifNotExists: Bool
    let condition: _SQLExpression?
    
    func sql() -> String {
        var chunks: [String] = []
        chunks.append("CREATE")
        if unique {
            chunks.append("UNIQUE")
        }
        chunks.append("INDEX")
        if ifNotExists {
            chunks.append("IF NOT EXISTS")
        }
        chunks.append(name.quotedDatabaseIdentifier)
        chunks.append("ON")
        chunks.append("\(table.quotedDatabaseIdentifier)(\((columns.map { $0.quotedDatabaseIdentifier } as [String]).joinWithSeparator(", ")))")
        if let condition = condition {
            chunks.append("WHERE")
            var arguments: StatementArguments? = nil // nil so that checkExpression.sql(&arguments) embeds literals
            chunks.append(condition.sql(&arguments))
        }
        return chunks.joinWithSeparator(" ")
    }
}

/// A built-in SQLite collation.
///
/// See https://www.sqlite.org/datatype3.html#collation
public enum SQLCollation : String {
    case Binary = "BINARY"
    case Nocase = "NOCASE"
    case Rtrim = "RTRIM"
}

/// An SQLite conflict resolution.
///
/// See https://www.sqlite.org/lang_conflict.html.
public enum SQLConflictResolution : String {
    case Rollback = "ROLLBACK"
    case Abort = "ABORT"
    case Fail = "FAIL"
    case Ignore = "IGNORE"
    case Replace = "REPLACE"
}

/// An SQL column type.
///
///     try db.create(table: "persons") { t in
///         t.column("id", .Integer).primaryKey()
///         t.column("title", .Text)
///     }
///
/// See https://www.sqlite.org/datatype3.html
public enum SQLColumnType : String {
    case Text = "TEXT"
    case Integer = "INTEGER"
    case Double = "DOUBLE"
    case Numeric = "NUMERIC"
    case Boolean = "BOOLEAN"
    case Blob = "BLOB"
    case Date = "DATE"
    case Datetime = "DATETIME"
}

/// A foreign key action.
///
/// See https://www.sqlite.org/foreignkeys.html
public enum SQLForeignKeyAction : String {
    case Cascade = "CASCADE"
    case Restrict = "RESTRICT"
    case SetNull = "SET NULL"
    case SetDefault = "SET DEFAULT"
}
