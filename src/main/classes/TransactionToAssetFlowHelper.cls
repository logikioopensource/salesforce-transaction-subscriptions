/**
 * @date 2024
 * Flow service for actions that result in upserts for Assets and Asset-related objects
 * i.e. Txn > Asset
 */
global with sharing class TransactionToAssetFlowHelper {
    global class FlowInput {
        @InvocableVariable(label='Record Id' required=true)
        global Id recordId;

        @InvocableVariable(label='Change Type' required=true)
        global String changeType;
        // Values: Add, Amend, Renew, Cancel?
    }

    /**
     * @description Calls create Asset API
     * @param requestInputs List of flow input parameters (only triggeringRecord for now)
     */
    @InvocableMethod(category='Logik.ai Packaged' label='Logik.ai Modify Asset Flow' description='Flow service for actions that result in upserts for Assets and Asset-related objects. i.e. Txn > Asset')
    global static void upsertAssets(FlowInput[] requestInputs) {
        /**
            To do:
                - Date validations
                - Account/Contact field checks
                - Exception handling
                - Whatever else is in Jira
         */

        // Hopefully, the FlowInput loop is always 1 record
        for (FlowInput each : requestInputs) {
            // Determine transactionId by context (not implemented)
            String transactionId;
            // String sobjectType = each.recordId.getSObjectType().getDescribe().getName();
            // if (sobjectType.equalsIgnoreCase('LGK__Transaction__c')) {
                transactionId = each.recordId;
            // }
            // else if (sobjectType.equalsIgnoreCase('Opportunity')) {
            // }
            // else if (sobjectType.equalsIgnoreCase('Order')) {
            // }

            // Get transaction lines, (parent) asset revisions, and assets
            LGK__TransactionLine__c[] childTransactionLineList = getChildTransactionLineList(transactionId);
            Map<Id, Asset> updatingAssetIdMap = getAssetIdMap(childTransactionLineList);

            // Create or Update Assets
            Map<Id, LGK__TransactionLine__c> transactionLineIdMap = new Map<Id, LGK__TransactionLine__c>{};
            Map<LGK__TransactionLine__c, Asset> transactionLineAssetMap = new Map<LGK__TransactionLine__c, Asset>{};
            Asset[] newAssetList = new Asset[]{};
            Map<Id, AssetRevisionHistory__c> newAssetRevisionMap = new Map<Id, AssetRevisionHistory__c>{};
            for (LGK__TransactionLine__c eachLine : childTransactionLineList) {
                transactionLineIdMap.put(eachLine.Id, eachLine);
                if (each.changeType.equalsIgnoreCase('Add') ||
                    (
                        eachLine.LGK__AssetId__c == null &&
                        String.isNotBlank(eachLine.SubscriptionBOMLineId__c)
                    )
                ) {
                    Asset newAsset = new Asset(
                        Name = eachLine.LGK__Product2Id__r.Name,
                        AccountId = eachLine.LGK__TransactionId__r.LGK__AccountId__c,
                        Product2Id = eachLine.LGK__Product2Id__c,
                        Quantity = eachLine.LGK__Quantity__c,
                        Price = eachLine.LGK__PricingNet__c,
                        LGK__TransactionLineId__c = eachLine.Id,
                        // LGK__UniqueId__c = eachLine.SubscriptionBOMLineId__c,
                        StartDate__c = eachLine.StartDate__c,
                        EndDate__c = eachLine.EndDate__c,
                        SubscriptionBOMLineId__c = eachLine.SubscriptionBOMLineId__c
                    );
                    if (String.isNotBlank(eachLine.LGK__ConfigurationId__c)) {
                        newAsset.LGK__ConfigurationId__c = eachLine.LGK__ConfigurationId__c;
                    }

                    transactionLineAssetMap.put(eachLine, newAsset);
                    newAssetList.add(newAsset);
                    newAssetRevisionMap.put(eachLine.Id, createAssetRevision(eachLine));
                }
                else if (each.changeType.equalsIgnoreCase('Amend') || each.changeType.equalsIgnoreCase('Renew')) {
                    Asset updatingAsset = updatingAssetIdMap.get(eachLine.LGK__AssetId__c);
                    if (updatingAsset != null) {
                        if (String.isNotBlank(eachLine.SubscriptionBOMLineId__c)) {
                            // Transaction Line is asset
                            updatingAsset = editAssetFieldValues(eachLine, updatingAsset);
                            updatingAssetIdMap.put(updatingAsset.Id, updatingAsset);
                            transactionLineAssetMap.put(eachLine, updatingAsset);
                        }
                        else {
                            // Transaction Line is revision history
                            AssetRevisionHistory__c updatingRevision = createAssetRevision(eachLine);
                            updatingRevision.LGK__AssetId__c = updatingAsset.Id;
                            newAssetRevisionMap.put(eachLine.Id, updatingRevision);
                        }
                    }
                }
            }

            Asset[] finalAssetUpsertList = new Asset[]{};
            try {
                if (!newAssetList.isEmpty()) {
                    finalAssetUpsertList.addAll(newAssetList);
                }
                finalAssetUpsertList.addAll(updatingAssetIdMap.values());
                
                if (!Test.isRunningTest()) {
                    Database.upsert(finalAssetUpsertList, true, AccessLevel.USER_MODE);
                }
                else {
                    Database.upsert(finalAssetUpsertList);
                }
            } catch(DmlException de) {
                de.setMessage(de.getMessage() + '\nError on Fields: ' + de.getDmlFieldNames(0));
                throw de;
            }

            // Re-query transaction lines to remove relationship fields like Transaction__r.Account (breaks DML security later)
            transactionLineIdMap = new Map<Id, LGK__TransactionLine__c>(
                [
                    SELECT Id, LGK__AssetId__c, LGK__ParentTransactionLineId__c
                    FROM LGK__TransactionLine__c
                    WHERE Id IN :transactionLineIdMap.keySet()
                    WITH USER_MODE
                ]
            );
            Map<String, Asset> transactionLineIdAssetMap = new Map<String, Asset>{};
            for (Asset eachAsset : finalAssetUpsertList) {
                // Update transaction line and map with asset 
                LGK__TransactionLine__c transactionLine = transactionLineIdMap.get(eachAsset.LGK__TransactionLineId__c);
                transactionLine.LGK__AssetId__c = eachAsset.Id;
                transactionLineIdAssetMap.put(transactionLine.Id, eachAsset);
                transactionLineIdMap.put(transactionLine.Id, transactionLine);

                // Update asset revision with asset Id
                AssetRevisionHistory__c assetRevision = newAssetRevisionMap.get(transactionLine.Id);
                if (assetRevision != null) {
                    assetRevision.LGK__AssetId__c = eachAsset.Id;
                    newAssetRevisionMap.put(transactionLine.Id, assetRevision);
                    // Update asset with product Id, if it changed
                    if (assetRevision.LGK__Product2Id__c != null && eachAsset.Product2Id != assetRevision.LGK__Product2Id__c) {
                        eachAsset.Product2Id = assetRevision.LGK__Product2Id__c;
                    }
                }
                
                if (String.isNotBlank(transactionLine.LGK__ParentTransactionLineId__c) && 
                    transactionLineIdAssetMap.containsKey(transactionLine.LGK__ParentTransactionLineId__c)
                ) {
                    eachAsset.ParentId = transactionLineIdAssetMap.get(transactionLine.LGK__ParentTransactionLineId__c).Id;
                }
            }

            // Update assets again with parent child relationship
            // Also update asset revisions and transaction lines
            try {
                if (!Test.isRunningTest()) {
                    Database.update(finalAssetUpsertList, true, AccessLevel.USER_MODE);
                    Database.insert(newAssetRevisionMap.values(), true, AccessLevel.USER_MODE);
                }
                else {
                    Database.update(finalAssetUpsertList);
                    Database.insert(newAssetRevisionMap.values());
                }

                Database.update(transactionLineIdMap.values(), true, AccessLevel.USER_MODE);
            } catch(DmlException de) {
                de.setMessage(de.getMessage() + '\nError on Fields: ' + de.getDmlFieldNames(0));
                throw de;
            }
        }
    }

    /**
     * @description Returns transaction lines
     */
    public static LGK__TransactionLine__c[] getChildTransactionLineList(String transactionId) {
        try {
            return [
                SELECT Id,  // Add fields as needed
                    LGK__TransactionId__c, LGK__Product2Id__c, 
                    LGK__Quantity__c, LGK__DeltaQuantity__c, LGK__PricingNet__c, LGK__DeltaPrice__c, 
                    LGK__TransactionId__r.LGK__AccountId__c, LGK__Product2Id__r.Name,    // Relationship fields
                    LGK__IsConfigured__c, LGK__ConfigurationId__c,  // Config fields
                    SubscriptionBOMLineId__c,  LGK__ParentTransactionLineId__c,
                    LGK__AssetId__c, StartDate__c, EndDate__c    // Asset/Revision fields
                    // LGK__AssetRevisionHistoryId__c, LGK__AssetRevisionHistoryId__r.LGK__AssetId__c
                    // LGK__ParentAssetRevisionHistoryId__c, LGK__ParentAssetRevisionHistoryId__r.LGK__AssetId__c
                FROM LGK__TransactionLine__c
                WHERE LGK__TransactionId__c = :transactionId
                WITH USER_MODE
                ORDER BY Id ASC
            ];
        } catch (QueryException qe) {
            qe.setMessage(qe.getMessage() + '\nInaccessible Fields: ' + qe.getInaccessibleFields());
            throw qe;
        }
    }

    public static Map<Id, Asset> getAssetIdMap(LGK__TransactionLine__c[] childTransactionLineList) {
        Set<String> assetIdSet = new Set<String>{};
        for (LGK__TransactionLine__c eachLine : childTransactionLineList) {
            if (eachLine.LGK__AssetId__c != null) {
                assetIdSet.add(eachLine.LGK__AssetId__c);
            }
            // if (eachLine.LGK__AssetRevisionHistoryId__c != null) {
            //     assetIdSet.add(eachLine.LGK__AssetRevisionHistoryId__r.LGK__AssetId__c);
            // }
            // if (eachLine.LGK__ParentAssetRevisionHistoryId__c != null) {
            //     assetIdSet.add(eachLine.LGK__ParentAssetRevisionHistoryId__r.LGK__AssetId__c);
            // }
        }

        try {
            return new Map<Id, Asset>([
                SELECT Id, AccountId, Product2Id, Quantity, Price, ParentId, 
                    LGK__TransactionLineId__c, LGK__ConfigurationId__c, SubscriptionBOMLineId__c //, LGK__UniqueId__c
                FROM Asset
                WHERE Id IN :assetIdSet
                WITH USER_MODE
            ]);
        } catch (QueryException qe) {
            qe.setMessage(qe.getMessage() + '\nInaccessible Fields: ' + qe.getInaccessibleFields());
            throw qe;
        }
    }

    // public static Asset getAssetFromTransactionLine(LGK__TransactionLine__c transactionLine, Map<Id, Asset> updatingAssetIdMap) {
    //     Asset updatingAsset;
    //     if (transactionLine.LGK__AssetId__c != null && updatingAssetIdMap.containsKey(transactionLine.LGK__AssetId__c)) {
    //         updatingAsset = updatingAssetIdMap.get(transactionLine.LGK__AssetId__c);
    //     }
    //     else if (transactionLine.LGK__AssetRevisionHistoryId__c != null && updatingAssetIdMap.containsKey(transactionLine.LGK__AssetRevisionHistoryId__r.LGK__AssetId__c)) {
    //         updatingAsset = updatingAssetIdMap.get(transactionLine.LGK__AssetRevisionHistoryId__r.LGK__AssetId__c);
    //     }
    //     else if (transactionLine.LGK__ParentAssetRevisionHistoryId__c != null && updatingAssetIdMap.containsKey(transactionLine.LGK__ParentAssetRevisionHistoryId__r.LGK__AssetId__c)) {
    //         updatingAsset = updatingAssetIdMap.get(transactionLine.LGK__ParentAssetRevisionHistoryId__r.LGK__AssetId__c);
    //     }

    //     return updatingAsset;
    // }

    public static Asset editAssetFieldValues(LGK__TransactionLine__c transactionLine, Asset updatingAsset) {
        // Decimal deltaQuantity = transactionLine.LGK__Quantity__c - updatingAsset.Quantity;
        // Decimal deltaPrice = transactionLine.LGK__PricingNet__c - updatingAsset.Price;

        // Update fields based on latest transaction line(s)
        updatingAsset.LGK__TransactionLineId__c = transactionLine.Id;
        // Account, Product are less likely to change
        updatingAsset.AccountId = transactionLine.LGK__TransactionId__r.LGK__AccountId__c;
        updatingAsset.Product2Id = transactionLine.LGK__Product2Id__c;
        updatingAsset.Quantity = transactionLine.LGK__Quantity__c;
        updatingAsset.Price = transactionLine.LGK__PricingNet__c;
        updatingAsset.StartDate__c = transactionLine.StartDate__c;
        updatingAsset.EndDate__c = transactionLine.EndDate__c;
        // updatingAsset.LGK__UniqueId__c = transactionLine.SubscriptionBOMLineId__c;
        updatingAsset.SubscriptionBOMLineId__c = transactionLine.SubscriptionBOMLineId__c;
        // Configuration Id, ParentId, RootAssetId
        if (String.isNotBlank(transactionLine.LGK__ConfigurationId__c)) {
            updatingAsset.LGK__ConfigurationId__c = transactionLine.LGK__ConfigurationId__c;
        }

        return updatingAsset;
    }

    public static AssetRevisionHistory__c createAssetRevision(LGK__TransactionLine__c transactionLine) {
        if (transactionLine.LGK__AssetId__c == null) {
            // Add
            return new AssetRevisionHistory__c(
                LGK__TransactionLineId__c = transactionLine.Id,
                LGK__Product2Id__c = transactionLine.LGK__Product2Id__c,
                LGK__DeltaQuantity__c = transactionLine.LGK__Quantity__c,  // For new assets, deltas should be based on main quantity/price
                LGK__DeltaPrice__c = transactionLine.LGK__PricingNet__c,
                StartDate__c = transactionLine.StartDate__c,
                EndDate__c = transactionLine.EndDate__c,
                LGK__ConfigurationId__c = transactionLine.LGK__ConfigurationId__c,
                SubscriptionBOMLineId__c = transactionLine.SubscriptionBOMLineId__c
                // Missing until later for new assets: LGK__AssetId__c
            );
        }
        else {
            // Update
            AssetRevisionHistory__c updatingAssetRevision = new AssetRevisionHistory__c(
                LGK__AssetId__c = transactionLine.LGK__AssetId__c,
                LGK__TransactionLineId__c = transactionLine.Id,
                StartDate__c = transactionLine.StartDate__c,
                EndDate__c = transactionLine.EndDate__c,
                LGK__ConfigurationId__c = transactionLine.LGK__ConfigurationId__c
                // SubscriptionBOMLineId__c is blank for revision lines
            );

            // If the delta fields are null on the transaction line, assume no change (aka 0)
            updatingAssetRevision.LGK__DeltaQuantity__c = transactionLine.LGK__DeltaQuantity__c != null ?
                transactionLine.LGK__DeltaQuantity__c :
                0;
            updatingAssetRevision.LGK__DeltaPrice__c = transactionLine.LGK__DeltaPrice__c != null ?
                transactionLine.LGK__DeltaPrice__c :
                0;

            return updatingAssetRevision;
        }
    }
}