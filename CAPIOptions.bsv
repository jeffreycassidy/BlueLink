package CAPIOptions;

import HList::*;
import ModuleContext::*;
import DefaultValue::*;

export CAPIOptions(..), ModuleContext::*, DefaultValue::*, HList::*;

typedef struct
{
    Bool showData;
    Bool showStatus;
    Bool showClientData;
    Bool showClientStatus;
    Bool showCommands;
    Bool showResponses;
    Bool showMMIO;
} CAPIOptions;

instance DefaultValue#(CAPIOptions);
    function CAPIOptions defaultValue = CAPIOptions {
        showData: False,
        showStatus: False,
        showClientData: False,
        showClientStatus: True,
        showMMIO: False,
        showCommands: False,
        showResponses: False
    };
endinstance

endpackage
