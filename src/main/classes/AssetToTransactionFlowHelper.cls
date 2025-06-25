/**
 * @date 2024
 * Flow service for actions that are initiated from assets, such as amend/renew
 * i.e. Asset > Txn
 */
global with sharing class AssetToTransactionFlowHelper {
    global class FlowInput {
        @InvocableVariable(label='Asset Id List' required=true)
        global String[] assetIdList;

        @InvocableVariable(label='Change Type' required=false)
        global String changeType;
        // Values: Add, Amend, Renew, Cancel?
    }
    
    global class FlowOutput {
        @InvocableVariable(label='New Transaction Id' required=false)
        global Id newTransactionId;
    }

    /**
     */
    @InvocableMethod(category='Logik.ai Packaged' label='Logik.ai Asset Operation Flow' description='Flow service for actions that are initiated from assets, such as amend/renew. i.e. Asset > Txn')
    global static FlowOutput[] initiateAssetOperation(FlowInput[] requestInputs) {
        FlowOutput[] flowOutputResults = new FlowOutput[]{};
        
        // Despite looping, there should only be one FlowInput per run
        // Otherwise, batch this if that turns out to be wrong
        for (FlowInput eachFlowInput : requestInputs) {
            try {
                // Collect selected assets and their original transaction lines
                String[] assetIdList = eachFlowInput.assetIdList;
                String assetQueryString = 'SELECT Id, Product2Id, Quantity, Price, AccountId' + 
                ', LGK__ConfigurationId__c, LGK__OpportunityId__c' +
                ', ParentId, RootAssetId' + 
                ' FROM Asset' +
                ' WHERE Id IN :assetIdList' +
                ' OR RootAssetId IN :assetIdList' + 
                ' ORDER BY Id ASC' ;  // Select descendants if config asset is selected

                Map<Id, Asset> assetMap = !Test.isRunningTest() ?
                    new Map<Id, Asset>((Asset[])Database.query(assetQueryString, AccessLevel.USER_MODE)) :
                    new Map<Id, Asset>((Asset[])Database.query(assetQueryString));

                Set<String> rootAssetIdSet = new Set<String>{};
                for (Asset eachAsset : assetMap.values()) {
                    rootAssetIdSet.add(eachAsset.RootAssetId);
                }

                // Query for unselected parent config asset(s), if any
                for (Asset eachDescendantAsset : [
                    SELECT Id, Product2Id, Quantity, Price, AccountId,
                        LGK__ConfigurationId__c, LGK__OpportunityId__c,
                        ParentId, RootAssetId
                    FROM Asset
                    WHERE RootAssetId IN :rootAssetIdSet
                    WITH USER_MODE
                    ORDER BY Id ASC
                ]) {
                    assetMap.put(eachDescendantAsset.Id, eachDescendantAsset);
                }

                Asset[] assetList = assetMap.values();

                // Create and insert transaction header
                LGK__Transaction__c newTransaction = new LGK__Transaction__c();
                if (!assetList.isEmpty()) {
                    newTransaction.LGK__AccountId__c = assetList[0].AccountId;
                }
                switch on eachFlowInput.changeType {
                    when 'Amend' {
                        newTransaction.LGK__TransactionType__c = 'Amendment';
                    }
                    when 'Renew' {
                        newTransaction.LGK__TransactionType__c = 'Renewal';
                        newTransaction.LGK__OpportunityId__c = assetList[0].LGK__OpportunityId__c;
                    }
                    when else {
                        newTransaction.LGK__TransactionType__c = 'Quote';
                    }
                }
                if (!Test.isRunningTest()) {
                    Database.insert(newTransaction, true, AccessLevel.USER_MODE);
                } else {
                    Database.insert(newTransaction);
                }
                

                // Assign to Flow Output
                FlowOutput thisFlowOutput = new FlowOutput();
                thisFlowOutput.newTransactionId = newTransaction.Id;
                // String[] configurationIdList = new String[]{};
                // configurationIdList.addAll(configurationIdSet);
                // thisFlowOutput.configurationIdList = configurationIdList;
                flowOutputResults.add(thisFlowOutput);

                // Create and insert lines
                LGK__TransactionLine__c[] newTransactionLineList = new LGK__TransactionLine__c[]{};
                Map<Id, Date> assetStartDateMap = new Map<Id, Date>{};      // AssetRevisionHistory.EndDate if Renew, otherwise AssetRevisionHistory.StartDate
                Map<Id, Date> assetEndDateMap = new Map<Id, Date>{};        // What should be the default EndDate on Renewals?
                Map<Id, Id> childParentMap = new Map<Id, Id>{};
                if (eachFlowInput.changeType.equalsIgnoreCase('Renew')) {
                    String assetRevisionHistoryQueryString = 'SELECT Id, LGK__AssetId__c, EndDate__c' +
                        ' FROM AssetRevisionHistory__c' +
                        ' WHERE LGK__AssetId__c IN :assetIdList' +
                        ' ORDER BY EndDate__c DESC';
                    AssetRevisionHistory__c[] assetRevisionHistoryList = !Test.isRunningTest() ? 
                        Database.query(assetRevisionHistoryQueryString, AccessLevel.USER_MODE) :
                        Database.query(assetRevisionHistoryQueryString);
                    
                    for (AssetRevisionHistory__c eachassetRevisionHistory : assetRevisionHistoryList) {
                        // Don't need to date compare other Revision History for a given Asset, since the first record is always the latest for that Asset
                        if (!assetStartDateMap.containsKey(eachassetRevisionHistory.LGK__AssetId__c)) {
                            assetStartDateMap.put(eachassetRevisionHistory.LGK__AssetId__c, eachassetRevisionHistory.EndDate__c.addDays(1));
                            assetEndDateMap.put(eachassetRevisionHistory.LGK__AssetId__c, eachassetRevisionHistory.EndDate__c.addDays(1));
                        }
                    }
                }
                else {
                    String assetRevisionHistoryQueryString = 'SELECT Id, LGK__AssetId__c, StartDate__c, EndDate__c' +
                        ' FROM AssetRevisionHistory__c' +
                        ' WHERE LGK__AssetId__c IN :assetIdList' +
                        ' ORDER BY StartDate__c DESC';
                    AssetRevisionHistory__c[] assetRevisionHistoryList = !Test.isRunningTest() ? 
                        Database.query(assetRevisionHistoryQueryString, AccessLevel.USER_MODE) :
                        Database.query(assetRevisionHistoryQueryString);
                    
                    for (AssetRevisionHistory__c eachassetRevisionHistory : assetRevisionHistoryList) {
                        if (!assetStartDateMap.containsKey(eachassetRevisionHistory.LGK__AssetId__c)) {
                            if (eachassetRevisionHistory.StartDate__c != null) {
                                assetStartDateMap.put(eachassetRevisionHistory.LGK__AssetId__c, eachassetRevisionHistory.StartDate__c.addDays(1));
                            }
                            if (eachassetRevisionHistory.EndDate__c != null) {
                                assetEndDateMap.put(eachassetRevisionHistory.LGK__AssetId__c, eachassetRevisionHistory.EndDate__c);
                            }
                        }
                    }
                }
                for (Asset eachAsset : assetList) {
                    // Populate map for later
                    if (String.isNotBlank(eachAsset.ParentId)) {
                        childParentMap.put(eachAsset.Id, eachAsset.ParentId);
                    }

                    // Update: Need to create the config + child lines
                    // if (String.isNotBlank(eachAsset.LGK__ConfigurationId__c)) {
                    //     // LGK__TransactionLine__c[] configurationLines = TransactionConfigurationFlowService.upsertConfiguration(eachAsset.LGK__ConfigurationId__c, newTransaction.Id);
                    //     // newTransactionLineList.addAll(configurationLines);
                    //     configurationIdSet.add(eachAsset.LGK__ConfigurationId__c);
                    // }
                    // // Also exclude config children
                    // else if (String.isBlank(eachAsset.ParentId)) {
                        LGK__TransactionLine__c newTransactionLine = new LGK__TransactionLine__c(
                            LGK__TransactionId__c = newTransaction.Id,
                            LGK__Product2Id__c = eachAsset.Product2Id,
                            LGK__Quantity__c = eachAsset.Quantity,
                            LGK__PricingNet__c = eachAsset.Price,
                            LGK__AssetId__c = eachAsset.Id,
                            LGK__ConfigurationId__c = eachAsset.LGK__ConfigurationId__c
                        );

                        if (String.isNotBlank(eachAsset.LGK__ConfigurationId__c) && eachAsset.Id == eachAsset.RootAssetId) {
                            // newTransactionLine.LGK__ConfigurationSolutionId__c = eachAsset.LGK__ConfigurationId__c;
                            newTransactionLine.LGK__IsConfigured__c = true;
                        }
                        else {
                            Asset rootAsset = assetMap.get(eachAsset.RootAssetId);
                            // newTransactionLine.LGK__ConfigurationSolutionId__c = rootAsset.LGK__ConfigurationId__c;
                            newTransactionLine.LGK__IsConfigured__c = false;
                        }
                        newTransactionLine.StartDate__c = assetStartDateMap.get(eachAsset.Id);
                        newTransactionLine.EndDate__c = assetEndDateMap.get(eachAsset.Id);
                        newTransactionLineList.add(newTransactionLine);
                    // }
                }

                if (!Test.isRunningTest()) {
                    Database.insert(newTransactionLineList, true, AccessLevel.USER_MODE);
                } else {
                    Database.insert(newTransactionLineList);
                }

                // If there were any child lines, update their parent and config info
                if (!childParentMap.isEmpty()) {
                    Map<Id, Id> parentAssetTransactionLineMap = new Map<Id, Id>{}; // <Asset, Transaction Line>
                    for (LGK__TransactionLine__c eachParent : [
                        SELECT Id, LGK__AssetId__c
                        FROM LGK__TransactionLine__c
                        WHERE LGK__AssetId__c IN :childParentMap.values()
                        WITH USER_MODE
                    ]) {
                        parentAssetTransactionLineMap.put(eachParent.LGK__AssetId__c, eachParent.Id);
                    }

                    // Loop over inserted lists to set parent relationship and config id
                    for (LGK__TransactionLine__c eachLine : newTransactionLineList) {
                        if (
                            childParentMap.get(eachLine.LGK__AssetId__c) != null
                        ) {
                            eachLine.LGK__ParentId2__c = parentAssetTransactionLineMap.get(
                                childParentMap.get(eachLine.LGK__AssetId__c)
                            );
                        }
                    }

                    // Passing through security to remove transaction Id (can't be updated)
                    SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, newTransactionLineList);
                    Database.update(securityDecision.getRecords(), true, AccessLevel.USER_MODE);
                }
            } catch (QueryException qe) {
                qe.setMessage(qe.getMessage() + '\nInaccessible Fields: ' + qe.getInaccessibleFields());
                throw qe;
            } catch (DmlException de) {
                de.setMessage(de.getMessage() + '\nError on Fields: ' + de.getDmlFieldNames(0));
                throw de;
            }
        }

        return flowOutputResults;
    }
}