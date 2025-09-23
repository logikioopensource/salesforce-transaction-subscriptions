import { LightningElement, wire, api } from "lwc";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import TRANSACTION_UUID_FIELD from "@salesforce/schema/LGK__Transaction__c.LGK__Id__c";

export default class TransactionScreenFlowRedirect extends NavigationMixin(LightningElement) {
    @api transactionId;
    @wire(getRecord, { recordId: "$transactionId", fields: [TRANSACTION_UUID_FIELD] }) wiredRecord;

    connectedCallback() {
        // Set URL from Screen Flow instead of PageReference
        if (this.transactionId) {
            this.waitForUUID();
        }
    }

    async waitForUUID() {
        this.pendingLoad = true;
        while (!this.wiredRecord.data?.fields?.LGK__Id__c?.value) {
            await new Promise(resolve => setTimeout(resolve, 500));
            await notifyRecordUpdateAvailable([{ recordId: this.transactionId }]);
        }

        window.open('/lightning/cmp/LGK__transactionAuraComponent?LGK__recordId=' + this.transactionId,
            '_parent');
    }
}