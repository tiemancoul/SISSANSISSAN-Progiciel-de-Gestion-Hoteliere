<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\Hotel;
use App\Models\User;
use Illuminate\Database\Seeder;

/** Demo data only. Every account uses the password "password": change it before any real use. */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $hotel = Hotel::create(['name' => 'Hôtel Démo Bamako', 'slug' => 'demo-bamako']);

        User::factory()->superAdmin()->create(['name' => 'Super Admin', 'email' => 'admin@sissansissan.com']);
        User::factory()->for($hotel)->create(['name' => 'Admin Démo', 'email' => 'gerant@demo.ml', 'role' => Role::HotelAdmin]);
        User::factory()->for($hotel)->create(['name' => 'Réception Démo', 'email' => 'reception@demo.ml', 'role' => Role::Receptionist]);
    }
}
