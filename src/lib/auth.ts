import { writable } from 'svelte/store'
import type { User } from '@supabase/supabase-js'
import { supabase } from './supabase'

export const user = writable<User | null>(null)

export async function signUp(email: string, password: string) {
    const { data, error } = await supabase.auth.signUp({
        email,
        password,
    })
    return { data, error }
}

export async function signIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
    })
    return { data, error }
}

export async function signOut() {
    const { error } = await supabase.auth.signOut()
    return { error }
}

export async function getUser() {
    const { data: { user: currentUser } } = await supabase.auth.getUser()
    return currentUser
}
