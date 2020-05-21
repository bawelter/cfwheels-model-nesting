<cfcomponent output="false">
	<cffunction name="init">
		<cfscript>
			this.version="2.1.0";
			return this;
		</cfscript>
	</cffunction>

	<cffunction name="$createSQLFieldList" returntype="string" access="public" output="false">
		<cfargument name="clause" type="string" required="true">
		<cfargument name="list" type="string" required="true">
		<cfargument name="include" type="string" required="true">
		<cfargument name="returnAs" type="string" required="true">
		<cfargument name="includeSoftDeletes" type="boolean" default="false">
		<cfargument name="useExpandedColumnAliases" type="boolean" default="#application.wheels.useExpandedColumnAliases#">
		<cfscript>
			// setup an array containing class info for current class and all the ones that should be included
			local.classes = [];
			if (Len(arguments.include)) {
				local.classes = $expandedAssociations(include=arguments.include, includeSoftDeletes=arguments.includeSoftDeletes);
			}
			ArrayPrepend(local.classes, variables.wheels.class);

			// if the developer passes in tablename.*, translate it into the list of fields for the developer, this is so we don't get *'s in the group by
			if (Find(".*", arguments.list)) {
				arguments.list = $expandProperties(list=arguments.list, classes=local.classes);
			}

			// add properties to select if the developer did not specify any
			if (!Len(arguments.list)) {
				local.iEnd = ArrayLen(local.classes);
				for (local.i = 1; local.i <= local.iEnd; local.i++) {
					local.classData = local.classes[local.i];
					arguments.list = ListAppend(arguments.list, local.classData.propertyList);
					if (StructCount(local.classData.calculatedProperties)) {
						for (local.key in local.classData.calculatedProperties) {
							if (local.classData.calculatedProperties[local.key].select) {
								arguments.list = ListAppend(arguments.list, local.key);
							}
						}
					}
				}
			}

			// go through the properties and map them to the database unless the developer passed in a table name or an alias in which case we assume they know what they're doing and leave the select clause as is
			if (!Find(".", arguments.list) && !Find(" AS ", arguments.list)) {
				local.rv = "";
				local.addedProperties = "";
				local.addedPropertiesByModel = {};
				local.iEnd = ListLen(arguments.list);
				for (local.i = 1; local.i <= local.iEnd; local.i++) {
					local.iItem = Trim(ListGetAt(arguments.list, local.i));

					// look for duplicates
					local.duplicateCount = ListValueCountNoCase(local.addedProperties, local.iItem);
					local.addedProperties = ListAppend(local.addedProperties, local.iItem);

					// loop through all classes (current and all included ones)
					local.jEnd = ArrayLen(local.classes);
					for (local.j = 1; local.j <= local.jEnd; local.j++) {
						local.toAppend = "";
						local.classData = local.classes[local.j];

						// create a struct for this model unless it already exists
						if (!StructKeyExists(local.addedPropertiesByModel, local.classData.modelName)) {
							local.addedPropertiesByModel[local.classData.modelName] = "";
						}

						// if we find the property in this model and it's not already added we go ahead and add it to the select clause
						if ((ListFindNoCase(local.classData.propertyList, local.iItem) || ListFindNoCase(local.classData.calculatedPropertyList, local.iItem)) && !ListFindNoCase(local.addedPropertiesByModel[local.classData.modelName], local.iItem)) {
							// if expanded column aliases is enabled then mark all columns from included classes as duplicates in order to prepend them with their class name
							local.flagAsDuplicate = false;
							if (arguments.clause == "select") {
								if (local.duplicateCount) {
									// always flag as a duplicate when a property with this name has already been added
									local.flagAsDuplicate  = true;
								} else if (local.j > 1) {
									if (arguments.useExpandedColumnAliases) {
										// when on included models and using the new setting we flag every property as a duplicate so that the model name always gets prepended
										local.flagAsDuplicate  = true;
									} else if (!arguments.useExpandedColumnAliases && arguments.returnAs != "query") {
										// with the old setting we only do it when we're returning object(s) since when creating instances on none base models we need the model name prepended
										local.flagAsDuplicate  = true;
									}
								}
							}
							if (local.flagAsDuplicate) {
								local.toAppend &= "[[duplicate]]" & local.j;
							}
							if (ListFindNoCase(local.classData.propertyList, local.iItem)) {
								local.toAppend &= local.classData.tableName & ".";
								if (ListFindNoCase(local.classData.columnList, local.iItem)) {
									local.toAppend &= local.iItem;
								} else {
									local.toAppend &= local.classData.properties[local.iItem].column;
									if (arguments.clause == "select") {
										local.toAppend &= " AS " & local.iItem;
									}
								}
							} else if (ListFindNoCase(local.classData.calculatedPropertyList, local.iItem)) {
								local.sql = Replace(local.classData.calculatedProperties[local.iItem].sql, ",", "[[comma]]", "all");
								if (arguments.clause == "select" || !REFind("^(SELECT )?(AVG|COUNT|MAX|MIN|SUM)\(.*\)", local.sql)) {
									local.toAppend &= "(" & local.sql & ")";
									if (arguments.clause == "select") {
										local.toAppend &= " AS " & local.iItem;
									}
								}
							}
							local.addedPropertiesByModel[local.classData.modelName] = ListAppend(local.addedPropertiesByModel[local.classData.modelName], local.iItem);
							break;
						}
					}
					if (Len(local.toAppend)) {
						local.rv = ListAppend(local.rv, local.toAppend);
					}
				}

				// let's replace eventual duplicates in the clause by prepending the class name
				if (Len(arguments.include) && arguments.clause == "select") {
					local.newSelect = "";
					local.addedProperties = "";
					local.iEnd = ListLen(local.rv);
					for (local.i = 1; local.i <= local.iEnd; local.i++) {
						local.iItem = ListGetAt(local.rv, local.i);

						// get the property part, done by taking everytyhing from the end of the string to a . or a space (which would be found when using " AS ")
						local.property = Reverse(SpanExcluding(Reverse(local.iItem), ". "));

						// check if this one has been flagged as a duplicate, we get the number of classes to skip and also remove the flagged info from the item
						local.duplicateCount = 0;
						local.matches = REFind("^\[\[duplicate\]\](\d+)(.+)$", local.iItem, 1, true);
						if (local.matches.pos[1] > 0) {
							local.duplicateCount = Mid(local.iItem, local.matches.pos[2], local.matches.len[2]);
							local.iItem = Mid(local.iItem, local.matches.pos[3], local.matches.len[3]);
						}

						if (!local.duplicateCount) {
							// this is not a duplicate so we can just insert it as is
							local.newItem = local.iItem;
							local.newProperty = local.property;
						} else {
							// this is a duplicate so we prepend the class name and then insert it unless a property with the resulting name already exist
							local.classData = local.classes[local.duplicateCount];

							// prepend class name to the property
							local.newProperty = local.classData.modelName & local.property;

							if (Find(" AS ", local.iItem)) {
								local.newItem = ReplaceNoCase(local.iItem, " AS " & local.property, " AS " & '`' & local.newProperty & '`');
							} else {
								local.newItem = local.iItem & " AS " & '`' & local.newProperty & '`';
							}
						}
						if (!ListFindNoCase(local.addedProperties, local.newProperty)) {
							local.newSelect = ListAppend(local.newSelect, local.newItem);
							local.addedProperties = ListAppend(local.addedProperties, local.newProperty);
						}
					}
					local.rv = local.newSelect;
				}
			} else {
				local.rv = arguments.list;
				if (arguments.clause == "groupBy" && Find(" AS ", local.rv)) {
					local.rv = REReplace(local.rv, variables.wheels.class.RESQLAs, "", "all");
				}
			}
			return local.rv;
		</cfscript>
	</cffunction>
</cfcomponent>
