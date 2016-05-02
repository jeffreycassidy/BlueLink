package SynthesisOptions;

import HList::*;
import ModuleContext::*;
import DefaultValue::*;

export MemSynthesisOptions(..), DSPSynthesisOptions(..), SynthesisOptions(..), HList::*, ModuleContext::*, DefaultValue::*;

typedef union tagged
{
    void AlteraStratixV;
    void BSVBehavioral;
} MemSynthesisOptions;

typedef union tagged
{
    void AlteraStratixV;
    void BSVBehavioral;
} DSPSynthesisOptions;

typedef struct
{
    Bool disableCheckCode;              // disable display/assertions whose only intention is testing
    Bool showStatus;
    Bool showData;
    Bool verbose;
    DSPSynthesisOptions dsp;
    MemSynthesisOptions mem;
} SynthesisOptions;

instance DefaultValue#(SynthesisOptions);
    function SynthesisOptions defaultValue = SynthesisOptions {
        disableCheckCode:   False,
        showStatus:         False,
        showData:           False,
        verbose:            False,      // show everything

        dsp: AlteraStratixV,
        mem: AlteraStratixV
    };
endinstance

endpackage
