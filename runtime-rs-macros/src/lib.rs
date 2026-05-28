// SPDX-License-Identifier: Apache-2.0
//
// Procedural macros for compact-runtime.

use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::quote;
use syn::{
    parse::{Parse, ParseStream},
    parse_macro_input, FnArg, Ident, ImplItem, ImplItemFn, ItemImpl, ReturnType, Token, Type,
};

/// Arguments to `#[witnesses(Name, PS = StateType)]`.
struct WitnessesArgs {
    /// The user's witness struct type (e.g. `MyWitnesses`). Currently
    /// parsed for clarity/documentation but not used by the macro's
    /// expansion — future revisions may use it for contract-scoped
    /// dispatch.
    #[allow(dead_code)]
    name: Ident,
    /// The private-state type the witnesses operate on.
    ps_type: Type,
}

impl Parse for WitnessesArgs {
    fn parse(input: ParseStream<'_>) -> syn::Result<Self> {
        let name: Ident = input.parse()?;
        let _comma: Token![,] = input.parse()?;
        let ps_ident: Ident = input.parse()?;
        if ps_ident != "PS" {
            return Err(syn::Error::new(
                ps_ident.span(),
                "expected `PS = <type>`",
            ));
        }
        let _eq: Token![=] = input.parse()?;
        let ps_type: Type = input.parse()?;
        Ok(WitnessesArgs { name, ps_type })
    }
}

/// `#[witnesses(StructName, PS = StateType)]` — generates an
/// `impl Witnesses<PS> for StructName` block forwarding each declared
/// inherent method to the user impl. The `Witnesses<PS>` trait itself is
/// emitted by `rust-passes.ss` in the generated contract crate.
#[proc_macro_attribute]
pub fn witnesses(attr: TokenStream, item: TokenStream) -> TokenStream {
    let args = parse_macro_input!(attr as WitnessesArgs);
    let impl_block = parse_macro_input!(item as ItemImpl);

    let user_type = &impl_block.self_ty;
    let ps_type = &args.ps_type;

    // Collect each fn declared in the user impl, generate a forwarding
    // method in the trait impl.
    let mut forwards: Vec<TokenStream2> = Vec::new();
    for it in &impl_block.items {
        if let ImplItem::Fn(ImplItemFn { sig, .. }) = it {
            let fn_name = &sig.ident;
            // Reconstruct the parameter list for the call site.
            let call_args: Vec<TokenStream2> = sig
                .inputs
                .iter()
                .map(|a| match a {
                    FnArg::Receiver(_) => quote! { self },
                    FnArg::Typed(pat_ty) => {
                        let pat = &pat_ty.pat;
                        quote! { #pat }
                    }
                })
                .collect();
            let inputs = &sig.inputs;
            let output = match &sig.output {
                ReturnType::Default => quote! { },
                ReturnType::Type(_, ty) => quote! { -> #ty },
            };
            forwards.push(quote! {
                fn #fn_name(#inputs) #output {
                    Self::#fn_name(#(#call_args),*)
                }
            });
        }
    }

    let trait_impl = quote! {
        impl Witnesses<#ps_type> for #user_type {
            #(#forwards)*
        }
    };

    let expanded = quote! {
        #impl_block
        #trait_impl
    };
    expanded.into()
}
