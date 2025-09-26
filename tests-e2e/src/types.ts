interface Type {
    'type-name': string;
}

interface Argument {
    name: string;
    type: Type;
}

interface Circuit {
    name: string;
    pure: boolean;
    arguments: Argument[];
    'result-type': Type;
}

export interface ContractInfo {
    circuits: Circuit[];
}
