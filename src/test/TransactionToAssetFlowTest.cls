@isTest private class TransactionToAssetFlowTest {
    final static String USERNAME = 'unittest' + String.valueOf(Date.today()) + '@logik.io';

    @TestSetup
    static void setupData() {
        // Create permission set for access to custom asset objects
        PermissionSet testPermissionSet = new PermissionSet(
            Name = 'TestPermSet' + DateTime.now().getTime(),
            Label = 'Test Permission Set ' + String.valueOf(Date.today())
        );
        insert testPermissionSet;
        insert new ObjectPermissions[]{
            new ObjectPermissions(
                ParentId = testPermissionSet.Id,
                SObjectType = 'Account',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true,
                PermissionsDelete = true,
                PermissionsViewAllRecords = true,
                PermissionsModifyAllRecords = true
            ),
            new ObjectPermissions(
                ParentId = testPermissionSet.Id,
                SObjectType = 'Asset',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true,
                PermissionsDelete = true,
                PermissionsViewAllRecords = true,
                PermissionsModifyAllRecords = true
            ),
            new ObjectPermissions(
                ParentId = testPermissionSet.Id,
                SObjectType = 'AssetRevisionHistory__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true,
                PermissionsDelete = true,
                PermissionsViewAllRecords = true,
                PermissionsModifyAllRecords = true
            )
        };
        // Create user to have the permission set assigned and to run tests as
        Profile sysAdmin = [SELECT Id FROM Profile WHERE Name='System Administrator'];
        User testUser = new User(
            Alias = 'tester',
            Email = USERNAME,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US',
            ProfileId = sysAdmin.Id, 
            TimeZoneSidKey ='America/Chicago',
            UserName = USERNAME
        );
        insert testUser;
        PermissionSet packagedPermissionSet = [SELECT Id FROM PermissionSet WHERE Name = 'LogikTransactionAssetFullAccess'];
        insert new PermissionSetAssignment[]{
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = testPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = packagedPermissionSet.Id
            )
        };

        // Setup actual test data
        System.runAs(testUser) {
            Product2 testProduct = new Product2(Name = 'TestProduct');
            insert testProduct;
            Account testAccount = new Account(Name = 'TestAccount');
            insert testAccount;
            LGK__Transaction__c newTransaction = new LGK__Transaction__c(
                TransactionType__c = 'Quote',
                LGK__AccountId__c = testAccount.Id
            );
            insert newTransaction;
            LGK__TransactionLine__c transactionLine = new LGK__TransactionLine__c(
                LGK__TransactionId__c = newTransaction.Id,
                LGK__Product2Id__c = testProduct.Id,
                LGK__Quantity__c = 5,
                LGK__PricingNet__c = 10,
                StartDate__c = Date.today(),
                EndDate__c = Date.today().addYears(3),
                SubscriptionBOMLineId__c = 'testSubBomLineId',
                LGK__ConfigurationId__c = 'testConfigId',
                LGK__IsConfigured__c = true
            );
            insert transactionLine;
        }
    }

    @isTest
    public static void testNewAsset() {
        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            LGK__Transaction__c testTransaction = [
                SELECT Id, LGK__AccountId__c
                FROM LGK__Transaction__c
                LIMIT 1
            ];
            LGK__TransactionLine__c childLine = [
                SELECT Id, LGK__Product2Id__c, LGK__ConfigurationId__c, StartDate__c, EndDate__c,
                    LGK__Quantity__c, DeltaQuantity__c, LGK__PricingNet__c, DeltaPrice__c, SubscriptionBOMLineId__c
                FROM LGK__TransactionLine__c
                LIMIT 1
            ];
            TransactionToAssetFlowHelper.FlowInput[] flowInputsList = new TransactionToAssetFlowHelper.FlowInput[]{
                new TransactionToAssetFlowHelper.FlowInput()
            };
            flowInputsList[0].recordId = testTransaction.Id;
            flowInputsList[0].changeType = 'Add';

            TransactionToAssetFlowHelper.upsertAssets(flowInputsList);
            // Assets
            Asset[] assetList = [
                SELECT Id, AccountId, Product2Id, Quantity, Price, TransactionLineId__c, SubscriptionBOMLineId__c
                FROM Asset
            ];
            System.assertEquals(1, assetList.size(),
                'Number of Assets created did not match the expected amount.');
            System.assertEquals(testTransaction.LGK__AccountId__c, assetList[0].AccountId,
                'Asset account did not match parent transaction.');
            System.assertEquals(childLine.LGK__Product2Id__c, assetList[0].Product2Id,
                'Asset product did not match transaction line.');
            System.assertEquals(childLine.LGK__Quantity__c, assetList[0].Quantity,
                'Asset quantity did not match transaction line.');
            System.assertEquals(childLine.LGK__PricingNet__c, assetList[0].Price,
                'Asset price did not match transaction line.');
            System.assertEquals(childLine.Id, assetList[0].TransactionLineId__c,
                'Asset transaction line was not set correctly.');
            System.assertEquals(childLine.SubscriptionBOMLineId__c, assetList[0].SubscriptionBOMLineId__c,
                'Asset Subscription BOM Line Id was not set correctly.');

            // Asset Revision History
            AssetRevisionHistory__c[] assetRevisionHistoryList = [
                SELECT TransactionLineId__c, 
                    DeltaQuantity__c,
                    DeltaPrice__c,
                    StartDate__c, EndDate__c
                FROM AssetRevisionHistory__c
            ];
            System.assertEquals(1, assetRevisionHistoryList.size(),
                'Number of Asset Revision History created did not match the expected amount.');
            System.assertEquals(childLine.Id, assetRevisionHistoryList[0].TransactionLineId__c,
                'Asset Revision History did not have the expected Transaction Line Id.');
            System.assertEquals(childLine.LGK__Quantity__c, assetRevisionHistoryList[0].DeltaQuantity__c,
                'Asset Revision History delta quantity did not match transaction line.');
            System.assertEquals(childLine.LGK__PricingNet__c, assetRevisionHistoryList[0].DeltaPrice__c,
                'Asset Revision History quantity did not match transaction line.');
            System.assertEquals(childLine.StartDate__c, assetRevisionHistoryList[0].StartDate__c,
                'Asset Revision History quantity did not match parent transaction.');
            System.assertEquals(childLine.EndDate__c, assetRevisionHistoryList[0].EndDate__c,
                'Asset Revision History quantity did not match parent transaction.');
        }
        Test.stopTest();
    }

    // Test starting amend

    @isTest
    public static void testCompleteAmend() {
        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            LGK__Transaction__c testTransaction = [
                SELECT Id, LGK__AccountId__c, TransactionType__c
                FROM LGK__Transaction__c
                LIMIT 1
            ];
            LGK__TransactionLine__c childLine = [
                SELECT Id, LGK__Quantity__c, LGK__PricingNet__c, LGK__ConfigurationId__c,
                    LGK__Product2Id__c, LGK__Product2Id__r.Name,
                    AssetId__c, StartDate__c, EndDate__c,
                    DeltaQuantity__c, DeltaPrice__c
                FROM LGK__TransactionLine__c
                LIMIT 1
            ];

            // Update transaction to be an amendment
            Asset newAsset = new Asset(
                Name = childLine.LGK__Product2Id__r.Name,
                AccountId = testTransaction.LGK__AccountId__c,
                Product2Id = childLine.LGK__Product2Id__c,
                Quantity = childLine.LGK__Quantity__c,
                Price = childLine.LGK__PricingNet__c,
                TransactionLineId__c = childLine.Id
            );
            insert newAsset;
            childLine.AssetId__c = newAsset.Id;
            childLine.LGK__Quantity__c = 10;    // Originally 5
            childLine.LGK__PricingNet__c = 8;     // Originally 10
            update childLine;
            LGK__TransactionLine__c revisionLine = new LGK__TransactionLine__c(
                LGK__TransactionId__c = testTransaction.Id,
                LGK__Product2Id__c = childLine.LGK__Product2Id__c,
                LGK__Quantity__c = 10,
                LGK__PricingNet__c = 8,
                AssetId__c = newAsset.Id,
                DeltaQuantity__c = 5,
                DeltaPrice__c = -2,
                StartDate__c = Date.today(),
                EndDate__c = Date.today().addYears(3)
            );
            insert revisionLine;

            testTransaction.TransactionType__c = 'Amendment';
            update testTransaction;

            TransactionToAssetFlowHelper.FlowInput[] flowInputsList = new TransactionToAssetFlowHelper.FlowInput[]{
                new TransactionToAssetFlowHelper.FlowInput()
            };
            flowInputsList[0].recordId = testTransaction.Id;
            flowInputsList[0].changeType = 'Amend';

            TransactionToAssetFlowHelper.upsertAssets(flowInputsList);

            // Assets
            Asset[] assetList = [
                SELECT Id, AccountId, Product2Id, Quantity, Price, TransactionLineId__c
                FROM Asset
                ORDER BY Id ASC
            ];
            System.assertEquals(1, assetList.size(),
                'New Asset was created during an existing asset amendment.');
            System.assertEquals(childLine.LGK__Quantity__c, assetList[0].Quantity,
                'Asset quantity did not update during Amend.');
            System.assertEquals(childLine.LGK__PricingNet__c, assetList[0].Price,
                'Asset price did not update during Amend.');

            // Asset Revision History
            AssetRevisionHistory__c[] assetRevisionHistoryList = [
                SELECT TransactionLineId__c, StartDate__c, EndDate__c,
                    DeltaQuantity__c, DeltaPrice__c
                FROM AssetRevisionHistory__c
            ];
            System.assertEquals(1, assetRevisionHistoryList.size(),
                'New Asset Revision History was not created during amend.');
            System.assertEquals(revisionLine.Id, assetRevisionHistoryList[0].TransactionLineId__c,
                'Asset Revision History did not have the expected Transaction Line Id.');
            // System.assertEquals(deltaQuantity, assetRevisionHistoryList[0].DeltaQuantity__c,
            System.assertEquals(revisionLine.DeltaQuantity__c, assetRevisionHistoryList[0].DeltaQuantity__c,
                'Asset Revision History delta quantity did not match transaction line.');
            System.assertEquals(revisionLine.DeltaPrice__c, assetRevisionHistoryList[0].DeltaPrice__c,
                'Asset Revision History delta price did not match transaction line.');
            System.assertEquals(revisionLine.StartDate__c, assetRevisionHistoryList[0].StartDate__c,
                'Asset Revision History start date did not match transaction line.');
            System.assertEquals(revisionLine.EndDate__c, assetRevisionHistoryList[0].EndDate__c,
                'Asset Revision History end date did not match transaction line.');
        }
        Test.stopTest();
    }
    
    // Test errors/validations
}