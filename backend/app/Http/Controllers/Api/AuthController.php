<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:100'],
        ]);

        $user = User::with('hotel')->where('email', $data['email'])->first();

        // Same message for every failure so the response never reveals which accounts exist.
        if (! $user || ! Hash::check($data['password'], $user->password) || ! $this->canLogIn($user)) {
            throw ValidationException::withMessages(['email' => 'Identifiants invalides ou compte désactivé.']);
        }

        return [
            'token' => $user->createToken($data['device_name'] ?? 'web')->plainTextToken,
            'user' => $user,
        ];
    }

    public function me(Request $request)
    {
        return $request->user()->load('hotel');
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->noContent();
    }

    private function canLogIn(User $user): bool
    {
        return $user->is_active && ($user->isSuperAdmin() || $user->hotel?->is_active);
    }
}
