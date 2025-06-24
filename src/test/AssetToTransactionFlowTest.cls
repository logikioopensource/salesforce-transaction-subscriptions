@isTest private class AssetToTransactionFlowTest {
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
                SObjectType = 'LGK__AssetRevisionHistory__c',
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

        // Create actual test data
        System.runAs(testUser) {
            Product2 testProduct = new Product2(Name = 'TestProduct');
            insert testProduct;
            Account testAccount = new Account(Name = 'TestAccount');
            insert testAccount;
            LGK__Transaction__c newTransaction = new LGK__Transaction__c(
                LGK__TransactionType__c = 'Quote',
                LGK__AccountId__c = testAccount.Id
            );
            insert newTransaction;
            LGK__TransactionLine__c transactionLine = new LGK__TransactionLine__c(
                LGK__TransactionId__c = newTransaction.Id,
                LGK__Product2Id__c = testProduct.Id,
                LGK__Quantity__c = 5,
                LGK__PricingNet__c = 10,
                LGK__StartDate__c = Date.today(),
                LGK__EndDate__c = Date.today().addYears(3)
            );
            insert transactionLine;

            Asset testAsset = new Asset(
                Name = testProduct.Name,
                Product2Id = testProduct.Id,
                AccountId = testAccount.Id,
                Quantity = transactionLine.LGK__Quantity__c,
                Price = transactionLine.LGK__PricingNet__c,
                LGK__TransactionLineId__c = transactionLine.Id
            );
            insert testAsset;
            insert new LGK__AssetRevisionHistory__c(
                LGK__AssetId__c = testAsset.Id,
                LGK__TransactionLineId__c = transactionLine.Id,
                LGK__DeltaQuantity__c = 1,
                LGK__DeltaPrice__c = 10,
                LGK__StartDate__c = Date.today(),
                LGK__EndDate__c = Date.today().addYears(1)
            );
        }
    }

    @isTest
    public static void testStartAdd() {
        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            String[] assetIdList = new String[]{};
            for (Asset each : [SELECT Id FROM Asset]) {
                assetIdList.add(each.Id);
            }
            AssetToTransactionFlowHelper.FlowInput[] flowInputsList = new AssetToTransactionFlowHelper.FlowInput[]{
                new AssetToTransactionFlowHelper.FlowInput()
            };
            flowInputsList[0].assetIdList = assetIdList;
            flowInputsList[0].changeType = 'Add';

            AssetToTransactionFlowHelper.FlowOutput[] flowOutputList = AssetToTransactionFlowHelper.initiateAssetOperation(flowInputsList);
            System.assert(assertNewTransaction(flowOutputList),
                'assertNewTransaction() did not return true for changeType Add');
        }
        Test.stopTest();
    }

    @isTest
    public static void testStartAmend() {
        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            String[] assetIdList = new String[]{};
            for (Asset each : [SELECT Id FROM Asset]) {
                assetIdList.add(each.Id);
            }
            AssetToTransactionFlowHelper.FlowInput[] flowInputsList = new AssetToTransactionFlowHelper.FlowInput[]{
                new AssetToTransactionFlowHelper.FlowInput()
            };
            flowInputsList[0].assetIdList = assetIdList;
            flowInputsList[0].changeType = 'Amend';

            AssetToTransactionFlowHelper.FlowOutput[] flowOutputList = AssetToTransactionFlowHelper.initiateAssetOperation(flowInputsList);
            System.assert(assertNewTransaction(flowOutputList),
                'assertNewTransaction() did not return true for changeType Amend');
        }
        Test.stopTest();
    }

    @isTest
    public static void testStartRenew() {
        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            String[] assetIdList = new String[]{};
            for (Asset each : [SELECT Id FROM Asset]) {
                assetIdList.add(each.Id);
            }
            AssetToTransactionFlowHelper.FlowInput[] flowInputsList = new AssetToTransactionFlowHelper.FlowInput[]{
                new AssetToTransactionFlowHelper.FlowInput()
            };
            flowInputsList[0].assetIdList = assetIdList;
            flowInputsList[0].changeType = 'Renew';

            AssetToTransactionFlowHelper.FlowOutput[] flowOutputList = AssetToTransactionFlowHelper.initiateAssetOperation(flowInputsList);
            System.assert(assertNewTransaction(flowOutputList),
                'assertNewTransaction() did not return true for changeType Renew');
        }
        Test.stopTest();
    }

    @isTest
    public static void testStartConfigurationAmend() {
        Product2 childTestProduct = new Product2(Name = 'Test Child Product');
        insert childTestProduct;
        Account testAccount = [SELECT Id FROM Account];

        Test.startTest();
        User testUser = [SELECT fields(Standard) FROM User WHERE UserName= :USERNAME];
        System.runAs(testUser) {
            // Add test data for config child
            LGK__Transaction__c testTransaction = [SELECT Id FROM LGK__Transaction__c LIMIT 1];
            LGK__TransactionLine__c testTransactionLine = new LGK__TransactionLine__c(
                LGK__TransactionId__c = testTransaction.Id,
                LGK__Product2Id__c = childTestProduct.Id,
                LGK__Quantity__c = 5,
                LGK__PricingNet__c = 10,
                LGK__StartDate__c = Date.today(),
                LGK__EndDate__c = Date.today().addYears(3)
            );
            insert testTransactionLine;

            String[] assetIdList = new String[]{};
            Asset parentTestAsset = [SELECT Id FROM Asset LIMIT 1],
                childAsset = new Asset(
                    Name = 'ConfigChildAsset',
                    Product2Id = childTestProduct.Id,
                    AccountId = testAccount.Id,
                    Quantity = 10,
                    Price = 15,
                    LGK__TransactionLineId__c = testTransactionLine.Id,
                    ParentId = parentTestAsset.Id
                );
            insert childAsset;
            assetIdList.add(parentTestAsset.Id);
            assetIdList.add(childAsset.Id);
        
            AssetToTransactionFlowHelper.FlowInput[] flowInputsList = new AssetToTransactionFlowHelper.FlowInput[]{
                new AssetToTransactionFlowHelper.FlowInput()
            };
            flowInputsList[0].assetIdList = assetIdList;
            flowInputsList[0].changeType = 'Amend';

            AssetToTransactionFlowHelper.FlowOutput[] flowOutputList = AssetToTransactionFlowHelper.initiateAssetOperation(flowInputsList);
            System.assert(assertNewTransaction(flowOutputList),
                'assertNewTransaction() did not return true for changeType Amend');
        }
        Test.stopTest();
    }

    // test multiple records at once

    public static Boolean assertNewTransaction(AssetToTransactionFlowHelper.FlowOutput[] flowOutputList) {
        Boolean results = true;
        System.assertEquals(1, flowOutputList.size(),
            'FlowOutputs did not return the expected list size.');
        // Other assertions?
        return results;
    }
}